require 'fileutils'
require 'digest/sha1'

class TsuruDeployClient

  def initialize(
    api_client:, logger:, environment:, host:, tsuru_home:, protocol: "https://"
  )
    target = URI.parse(protocol + environment + "-api." + host)

    targets_path = File.join(ENV["HOME"], ".tsuru_targets")
    unless File.exists?(targets_path) and \
    File.read(targets_path).include?(target.to_s)
      system "tsuru target-add #{environment} #{target}"
    end

    target_path = File.join(ENV["HOME"], ".tsuru_target")
    unless File.exists?(target_path) and \
    File.read(target_path).include?(target.to_s)
      system "tsuru target-set #{environment}"
    end

    @api_client = api_client
    @logger = logger
    @tsuru_home = tsuru_home
  end

  def api_client
    return @api_client
  end

  def logger
    return @logger
  end

  def deploy_app(user:, app:, env_vars: {}, postgres: '', git: false, units: 3)
    self.logger.info("Going to deploy #{app[:name]}")
    self.logger.info("Login user #{user[:email]} of the team #{user[:team]}")
    self.api_client.login(user[:email], user[:password])

    if not self.api_client.list_apps().include? app[:name]
      self.logger.info("Create application #{app[:name]} " \
        "on the platform #{app[:platform]}")
      self.api_client.create_app(app[:name], app[:platform])
    end

    # Set environment variables, if needed
    if env_vars.length > 0
      env_vars.each do |key,value|
        self.api_client.set_env_var(app[:name], key, value)
      end
    end

    if postgres != ''
      instance_name = postgres
      unless self.api_client.list_service_instances().include? instance_name
          self.logger.info("Add postgres service instance #{instance_name}")
          self.api_client.add_service_instance("postgresql", instance_name)
      end

      unless self.api_client.app_has_service(app[:name], instance_name)
        self.logger.info("Bind service #{instance_name} to #{app[:name]}")
        self.api_client.bind_service_to_app(instance_name, app[:name])
      end
    end

    system "echo '#{@api_client.get_token}' > ${HOME}/.tsuru_token"

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
      self.api_client.add_units(units - deployed_units, app[:name])
    end
  end

  def import_pg_dump(app_name, postgres_instance_name, ssh_config)
    system "python -c \"import boto;boto.connect_s3().get_bucket('digital-marketplace-stuff').get_key('full.dump').get_contents_to_filename('#{@tsuru_home}/full.dump')\""
    postgres_ip = @api_client.get_env_vars(app_name)["PG_HOST"]
    db_name = canonicalize_db_name(postgres_instance_name)
    scp_cmd = "scp -F #{ssh_config} #{@tsuru_home}/full.dump #{postgres_ip}:~/full.dump"
    self.logger.info("SCP postgres dump file over: #{scp_cmd}")
    system scp_cmd
    restore_cmd = "ssh -F #{ssh_config} #{postgres_ip} 'pg_restore -a -U postgres -d #{db_name} -Fc ~/full.dump'"
    self.logger.info("Let's restore the data from backup: #{restore_cmd}")
    system restore_cmd
  end

  private

  def app_deploy(path, app_name)
    FileUtils.cd(path)
    system "tsuru app-deploy * -a #{app_name}"
  end

  def git_deploy(path, git_repo, key)
    FileUtils.cd(path)
    begin
      system "ssh-add #{key}"
      system "GIT_SSH_COMMAND='ssh -i #{key} -F " +
        "#{@tsuru_home}/.ssh/config' git push #{git_repo} master"
    ensure
      system "ssh-add -d #{key}"
    end
  end

  # See https://github.com/tsuru/postgres-api/blob/master/postgresapi/models.py#L45
  def canonicalize_db_name(name)
    name += Digest::SHA1.hexdigest(name)[0..9]
    return name.gsub(/-/, '_')
  end

end
