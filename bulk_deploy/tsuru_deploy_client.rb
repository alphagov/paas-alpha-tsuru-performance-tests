require 'fileutils'
require 'digest/sha1'
require 'aws-sdk'
require 'tsuru_helper'

class TsuruDeployClient

  attr_accessor :api_client, :logger

  def initialize(
    api_client:, logger:, environment:, host:, tsuru_home:, protocol: "https://"
  )
    @api_client = api_client
    @logger = logger
    @tsuru_home = tsuru_home

    tsuru_output = File.open(File.join(@tsuru_home, "output"), 'a')
    logger.info("Main output file = #{tsuru_output.path}")
    @tsuru_command = TsuruCommandLine.new(
        { 'HOME' => @tsuru_home },
        {
          :verbose => ENV['VERBOSE'],
          :output_file => tsuru_output
        }
    )

    target = URI.parse(protocol + environment + "-api." + host)
    @tsuru_command.target_remove(environment)
    raise @tsuru_command.stderr if @tsuru_command.exit_status != 0
    @tsuru_command.target_add(environment, target.to_s)
    raise @tsuru_command.stderr if @tsuru_command.exit_status != 0
    @tsuru_command.target_set(environment)
    raise @tsuru_command.stderr if @tsuru_command.exit_status != 0
  end

  def deploy_app(user:, app:, env_vars: {}, postgres: '', git: false, units: 3)
    self.logger.info("Going to deploy #{app[:name]}")
    self.logger.info("Login user #{user[:email]} of the team #{user[:team]}")
    new_api_client = api_client.clone
    new_api_client.login(user[:email], user[:password])

    new_tsuru_command = @tsuru_command.clone
    new_tsuru_command.copy_and_set_home(File.join(@tsuru_home, user[:email]))

    tsuru_output = File.open(File.join(@tsuru_home, user[:email], "output"), 'a')
    logger.info("#{user[:email]} output file = #{tsuru_output.path}")
    new_tsuru_command.output_file = tsuru_output

    git_command = GitCommandLine.new(app[:dir], {
      'HOME' => @tsuru_home,
      'GIT_SSH' => user[:ssh_wrapper]},
      {
        :verbose => ENV['VERBOSE'],
        :output_file => tsuru_output
      })

    new_tsuru_command.login(user[:email], user[:password])

    if not new_api_client.list_apps().include? app[:name]
      self.logger.info("Create application #{app[:name]} " \
        "on the platform #{app[:platform]}")
      new_api_client.create_app(app[:name], app[:platform])
    end

    # Set environment variables, if needed
    if env_vars.length > 0
      env_vars.each do |key,value|
        new_api_client.set_env_var(app[:name], key, value)
      end
    end

    if postgres != ''
      instance_name = postgres
      unless new_api_client.list_service_instances().include? instance_name
          self.logger.info("Add postgres service instance #{instance_name}")
          new_api_client.add_service_instance("postgresql", instance_name)
      end

      unless new_api_client.app_has_service(app[:name], instance_name)
        self.logger.info("Bind service #{instance_name} to #{app[:name]}")
        new_api_client.bind_service_to_app(instance_name, app[:name])
      end
    end

    if git
      self.logger.info("Deploy #{app[:name]} via git")
      git_deploy(
        new_api_client.get_app_repository(app[:name]),
        git_command
      )
    else
      self.logger.info("Deploy #{app[:name]} via app-deploy")
      app_deploy(app[:dir], app[:name], new_tsuru_command)
    end

    deployed_units = self.api_client.get_app_info(app[:name])["units"].length
    if deployed_units < units
      new_api_client.add_units(units - deployed_units, app[:name])
    end

    tsuru_output.close
  end

  def remove_app(user:, app:, postgres: '')
    self.logger.info("Going to remove #{app[:name]}")
    self.logger.info("Login user #{user[:email]} of the team #{user[:team]}")
    new_api_client = api_client.clone
    new_api_client.login(user[:email], user[:password])

    if not new_api_client.list_apps().include? app[:name]
      self.logger.warn("Application #{app[:name]} does not exist " \
        "on the platform #{app[:platform]}")
      return
    end

    new_tsuru_command = @tsuru_command.clone
    new_tsuru_command.copy_and_set_home(File.join(@tsuru_home, user[:email]))

    tsuru_output = File.open(File.join(@tsuru_home, user[:email], "output"), 'a')
    logger.info("#{user[:email]} output file = #{tsuru_output.path}")
    new_tsuru_command.output_file = tsuru_output

    new_tsuru_command.login(user[:email], user[:password])
    app_remove(app[:name], new_tsuru_command)

    if postgres != ''
      @logger.info "Remove service #{postgres}"
      retries=5
      begin
        sleep 1
        @api_client.remove_service_instance(postgres)
      rescue Exception => e
        retry if (retries -= 2) > 0
        @logger.error "Cannot remove service #{postgres}. Exception: #{e}"
      end
    end

  end

  def import_pg_dump(app_name, postgres_instance_name)
    # Download database dump from S3
    File.open(File.join(@tsuru_home, "full.dump"), "wb") do |file|
      reap = Aws::S3::Client.new.get_object(
        {
          bucket:"digital-marketplace-stuff",
          key: "full.dump"
        },
        target: file
      )
    end

    postgres_ip = @api_client.get_env_vars(app_name)["PG_HOST"]
    db_name = @api_client.get_env_vars(app_name)["PG_DATABASE"]
    # Ugly hack incoming!
    ssh_config_dir = `find ~ -name tsuru-ansible | head -n 1 | tr -d '\n'`

    # Use scp to upload the database dump to posgres box
    scp_cmd = "cd #{ssh_config_dir} && scp -F ssh.config "\
              "#{@tsuru_home}/full.dump #{postgres_ip}:~/full.dump"
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
  def import_pg_dump_via_app(app_name, dump_url, auth_header)
    remote_command =
      "sudo apt-get install postgresql-client -y && "\
      "echo \"*:*:*:${PG_PASSWORD}\" > ~/.pgpass && chmod 600 ~/.pgpass && "\
      "curl #{dump_url} -H '#{auth_header}' | "\
      "pg_restore -O -a -h ${PG_HOST} -p ${PG_PORT} -U ${PG_USER} -d ${PG_DATABASE}"
    @tsuru_command.app_run_once(app_name, remote_command)
    raise @tsuru_command.stderr if @tsuru_command.exit_status != 0
  end

  private

  def app_deploy(path, app_name, tsuru_command)
    tsuru_command.app_deploy(app_name, path, '*')
    raise tsuru_command.stderr if tsuru_command.exit_status != 0
  end

  def app_remove(app_name, tsuru_command)
    tsuru_command.app_remove(app_name)
    raise tsuru_command.stderr if tsuru_command.exit_status != 0
  end

  def git_deploy(git_repo, git_command)
    git_command.push(git_repo)
    raise git_command.stderr if git_command.exit_status != 0
  end

end
