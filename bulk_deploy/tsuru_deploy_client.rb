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

    FileUtils.mkdir_p(tsuru_home)
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

  def deploy_app(app:, env_vars: {}, postgres: '', elasticsearch: '', git: false, units: 3)
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
        bind_service_to_app("postgresql", postgres, app)
      end

      if elasticsearch != ''
        bind_service_to_app("elasticsearch", elasticsearch, app)
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
        raise tsuru_command.stderr if tsuru_command.exit_status != 0
      end
    end

    deployed_units = self.api_client.get_app_info(app[:name])["units"].length
    if deployed_units < units
      self.logger.info("Increasing units of #{app[:name]} #{deployed_units} => #{units}")
      api_client.add_units(units - deployed_units, app[:name])
    end

    self.logger.info("Finished deploying #{app[:name]}")
  end

  def bind_service_to_app(service_name, instance_name, app)
    unless api_client.list_service_instances().include? instance_name
      self.logger.info("Add #{service_name} service instance #{instance_name}")
      api_client.add_service_instance(service_name, instance_name)
    end

    unless api_client.app_has_service(app[:name], instance_name)
      self.logger.info("Bind service #{instance_name} to #{app[:name]}")
      api_client.bind_service_to_app(instance_name, app[:name])
    end
  end

  def remove_app(app:, postgres: '', elasticsearch: '')
    self.logger.info("Going to remove #{app[:name]}")

    if api_client.list_apps().include? app[:name]
      self.logger.warn("Application #{app[:name]} does not exist " \
                       "on the platform #{app[:platform]}")
      tsuru_command.app_remove(app[:name])
      raise tsuru_command.stderr if tsuru_command.exit_status != 0
    end

    if postgres != ''
      remove_service(postgres)
    end

    if elasticsearch != ''
      remove_service(elasticsearch)
    end
  end

  def remove_service(service)
    logger.info "Remove service #{service}"
    retries=5
    begin
      sleep 1
      api_client.remove_service_instance(service)
    rescue Exception => e
      retry if (retries -= 2) > 0
      logger.error "Cannot remove service #{service}. Exception: #{e}"
    end
  end

  # Uses tsuru app-run command to download and import the DB dump.
  #
  # To download the DB dump you need:
  #  * a dump_url
  #  * a secret authentication header in the form of "Header: secret"
  #
  # As pg_restore returns errors, we check that the DB is imported by querying one table
  #
  def import_pg_dump(app_name, dump_url, auth_header)
    remote_command =
      "sudo apt-get install postgresql-client -y && "\
      "echo \"*:*:*:${PG_PASSWORD}\" > ~/.pgpass && chmod 600 ~/.pgpass && "\
      "curl #{dump_url} -H '#{auth_header}' | "\
      "( pg_restore -O -a -h ${PG_HOST} -p ${PG_PORT} -U ${PG_USER} -d ${PG_DATABASE} || "\
      "  psql ${PG_DATABASE} -h ${PG_HOST} -p ${PG_PORT} -U ${PG_USER} -t -c 'SELECT count(*) > 2000 from users;' | grep -q t )"
    self.logger.info("Going to import Postgres data")
    tsuru_command.app_run_once(app_name, remote_command)
    raise tsuru_command.stderr if tsuru_command.exit_status != 0
  end

  def import_elasticsearch_data(pg_app_name, es_app_name)
    search_api_url = "https://" + api_client.get_app_url(es_app_name)
    search_api_token = api_client.get_env_vars(es_app_name)["DM_SEARCH_API_AUTH_TOKENS"]
    api_url = "http://0.0.0.0:8888"
    api_token = api_client.get_env_vars(pg_app_name)["DM_API_AUTH_TOKENS"]
    remote_command = "python scripts/index_services.py #{search_api_url} #{search_api_token} #{api_url} #{api_token} --serial"
    self.logger.info("Going to import Elasticsearch data")
    tsuru_command.app_run_once(pg_app_name, remote_command)
    raise tsuru_command.stderr if tsuru_command.exit_status != 0
  end

end
