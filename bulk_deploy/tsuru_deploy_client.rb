require 'fileutils'
require 'digest/sha1'
require 'aws-sdk'
require 'tsuru_helper'

class TsuruDeployClient

  attr_reader :api_client, :tsuru_command, :tsuru_home
  attr_reader :ssh_wrapper, :logger

  def initialize(
    logger:, tsuru_user:, tsuru_password:, ssh_wrapper:, working_dir:,
    environment:, host:, protocol: "https://"
  )
    @logger = logger
    @tsuru_user = tsuru_user
    @tsuru_password = tsuru_password
    @ssh_wrapper = ssh_wrapper
    @working_dir = working_dir
    @tsuru_home = File.join(working_dir, tsuru_user)
    @environment = environment
    @target = URI.parse(protocol + environment + "-api." + host)

    @api_client = TsuruAPIClient.new(
      logger: LOGGER,
      environment: ENVIRONMENT,
      host: TSURU_HOST
    )

    @tsuru_output = File.open(File.join(tsuru_home, "output"), 'a')
    logger.info("Output file for #{tsuru_user} = #{@tsuru_output.path}")
    @tsuru_command = TsuruCommandLine.new(
      { 'HOME' => tsuru_home },
      {
        :verbose => ENV['VERBOSE'],
        :output_file => @tsuru_output
      }
    )
    tsuru_command.target_remove(environment)
    raise tsuru_command.stderr if tsuru_command.exit_status != 0
    tsuru_command.target_add(environment, @target.to_s)
    raise tsuru_command.stderr if tsuru_command.exit_status != 0
    tsuru_command.target_set(environment)
    raise tsuru_command.stderr if tsuru_command.exit_status != 0
    tsuru_command

    self.logger.info("Login user #{tsuru_user}")
    tsuru_command.login(tsuru_user, tsuru_password)
    api_client.login(tsuru_user, tsuru_password)

  end

  def deploy_app(app:, env_vars: {}, postgres: '', git: false, units: 3)
    self.logger.info("Going to deploy #{app[:name]}. Check #{@tsuru_output.path} for output.")

    if not api_client.list_apps().include? app[:name]
      self.logger.info("Create application #{app[:name]} " \
                       "on the platform #{app[:platform]}")
      api_client.create_app(app[:name], app[:platform])
    end

    # Check if the app is already running, skip if it is
    deployed_units = self.api_client.get_app_info(app[:name])["units"].length
    if deployed_units > 1
      self.logger.info("#{app[:name]} is already deployed, skipping. Remove app to redeploy.")
    else
      # Set environment variables, if needed
      if env_vars.length > 0
        env_vars.each do |key,value|
          api_client.set_env_var(app[:name], key, value)
        end
      end

      if postgres != ''
        instance_name = postgres
        unless api_client.list_service_instances().include? instance_name
          self.logger.info("Add postgres service instance #{instance_name}")
          api_client.add_service_instance("postgresql", instance_name)
        end

        unless api_client.app_has_service(app[:name], instance_name)
          self.logger.info("Bind service #{instance_name} to #{app[:name]}")
          api_client.bind_service_to_app(instance_name, app[:name])
        end
      end

      if git
        self.logger.info("Deploy #{app[:name]} via git. Check #{@tsuru_output.path} for output.")
        git_command = GitCommandLine.new(app[:dir], {
          'HOME' => tsuru_home,
          'GIT_SSH' => ssh_wrapper
        },
        {
          :verbose => ENV['VERBOSE'],
          :output_file => tsuru_command.output_file
        })
        git_command.push(api_client.get_app_repository(app[:name]))
        raise git_command.stderr if git_command.exit_status != 0
      else
        self.logger.info("Deploy #{app[:name]} via app-deploy. Check #{@tsuru_output.path} for output.")
        tsuru_command.app_deploy(app[:name], app[:dir], '*')
      end
    end

    deployed_units = self.api_client.get_app_info(app[:name])["units"].length
    if deployed_units < units
      self.logger.info("Increasing units of #{app[:name]} #{deployed_units} => #{units}")
      api_client.add_units(units - deployed_units, app[:name])
    end

    self.logger.info("Finished deploying #{app[:name]}")
  end

  def remove_app(app:, postgres: '')
    self.logger.info("Going to remove #{app[:name]}")

    if api_client.list_apps().include? app[:name]
      self.logger.warn("Application #{app[:name]} does not exist " \
                       "on the platform #{app[:platform]}")
      tsuru_command.app_remove(app[:name])
      raise tsuru_command.stderr if tsuru_command.exit_status != 0
    end

    if postgres != ''
      logger.info "Remove service #{postgres}"
      retries=5
      begin
        sleep 1
        api_client.remove_service_instance(postgres)
      rescue Exception => e
        retry if (retries -= 2) > 0
        logger.error "Cannot remove service #{postgres}. Exception: #{e}"
      end
    end
  end

  def import_pg_dump(app_name, postgres_instance_name)
    # Download database dump from S3
    File.open(File.join(tsuru_home, "full.dump"), "wb") do |file|
      reap = Aws::S3::Client.new.get_object(
        {
          bucket:"digital-marketplace-stuff",
          key: "full.dump"
        },
        target: file
      )
    end

    postgres_ip = api_client.get_env_vars(app_name)["PG_HOST"]
    db_name = api_client.get_env_vars(app_name)["PG_DATABASE"]
    # Ugly hack incoming!
    ssh_config_dir = `find ~ -name tsuru-ansible | head -n 1 | tr -d '\n'`

    # Use scp to upload the database dump to posgres box
    scp_cmd = "cd #{ssh_config_dir} && scp -F ssh.config "\
      "#{tsuru_home}/full.dump #{postgres_ip}:~/full.dump"
    self.logger.info("SCP postgres dump file over: #{scp_cmd}")
    if !system(scp_cmd)
      raise "Failed to upload database dump via scp"
    end

    # Run pg_restore on the postgres box to load the data
    restore_cmd = "cd #{ssh_config_dir} && ssh -F ssh.config #{postgres_ip} "\
                  "'pg_restore -a -U postgres -d #{db_name} -a --disable-triggers ~/full.dump'"
    self.logger.info("Let's restore the data from backup: #{restore_cmd}")
    system(restore_cmd)
  end

  # Uses tsuru app-run command to download and import the DB dump.
  #
  # To download the DB dump you need:
  #  * a dump_url
  #  * a secret authentication header in the form of "Header: secret"
  #
  # As pg_restore returns errors, we check that the DB is imported by querying one table
  #
  def import_pg_dump_via_app(app_name, dump_url, auth_header)
    remote_command =
      "sudo apt-get install postgresql-client -y && "\
      "echo \"*:*:*:${PG_PASSWORD}\" > ~/.pgpass && chmod 600 ~/.pgpass && "\
      "curl #{dump_url} -H '#{auth_header}' | "\
      "( pg_restore -O -a -h ${PG_HOST} -p ${PG_PORT} -U ${PG_USER} -d ${PG_DATABASE} || "\
      "  psql ${PG_DATABASE} -h ${PG_HOST} -p ${PG_PORT} -U ${PG_USER} -t -c 'SELECT count(*) > 2000 from users;' | grep -q t )"
    tsuru_command.app_run_once(app_name, remote_command)
    raise tsuru_command.stderr if tsuru_command.exit_status != 0
  end

end
