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

    @tsuru_command = TsuruCommandLine.new(
        { 'HOME' => @tsuru_home },
        { :verbose => ENV['VERBOSE'] }
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
        app[:dir],
        self.api_client.get_app_repository(app[:name]),
        user[:key]
      )
    else
      self.logger.info("Deploy #{app[:name]} via app-deploy")
      app_deploy(app[:dir], app[:name])
    end

    deployed_units = self.api_client.get_app_info(app[:name])["units"].length
    if deployed_units < units
      new_api_client.add_units(units - deployed_units, app[:name])
    end
  end

  def import_pg_dump(app_name, postgres_instance_name, ssh_config)
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
    ssh_config_dir = File.dirname(File.expand_path(ssh_config))

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

  private

  def app_deploy(path, app_name)
    FileUtils.cd(path)
    if !system("tsuru app-deploy * -a #{app_name}")
      raise "Failed to deploy the app"
    end
  end

  def git_deploy(path, git_repo, key)
    FileUtils.cd(path)
    begin
      if !system("ssh-add #{key}")
        raise "Failed to add key"
      end
      if !system("GIT_SSH_COMMAND='ssh -i #{key} -F " +
        "#{@tsuru_home}/.ssh/config' git push #{git_repo} master")
        raise "Failed to deploy the app"
      end
    ensure
      if !system("ssh-add -d #{key}")
        raise "Failed to remove key"
      end
    end
  end

end
