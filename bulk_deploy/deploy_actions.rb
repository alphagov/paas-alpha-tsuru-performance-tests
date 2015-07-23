require 'fileutils'
require 'yaml'
require_relative 'tsuru_api_client'
require_relative 'tsuru_api_service'
require_relative 'tsuru_deploy_client'

class DeployActions

  def initialize(options)
    @options = options
    @logger = Logger.new(STDOUT)
    case options[:log_level].downcase
      when 'debug'
        @logger.level = Logger::DEBUG
      when 'info'
        @logger.level = Logger::INFO
      when 'warn'
        @logger.level = Logger::WARN
      when 'error'
        @logger.level = Logger::ERROR
      when 'fatal'
        @logger.level = Logger::FATAL
      else
        raise "Error: Unknown log level: #{options[:log_level]}"
    end

    @tsuru_home = Dir.mktmpdir
    ENV["HOME"] = @tsuru_home
  end

  def apply()
    environment       = @options[:environment]
    host_suffix       = @options[:host_suffix]
    api_token         = @options[:api_token]
    search_api_token  = @options[:search_api_token]
    ssh_config        = @options[:ssh_config]
    team_count        = @options[:team_count]
    apps_per_team     = @options[:apps_per_team]
    users_per_team    = @options[:users_per_team]
    units_per_app     = @options[:units_per_app]
    state_file        = @options[:state_file]

    FileUtils.rm_rf(@tsuru_home)
    Dir.mkdir(@tsuru_home) unless File.exist? @tsuru_home

    # Initialize objects

    api_client = TsuruAPIClient.new(
      logger: @logger,
      environment: environment,
      host: host_suffix
    )

    api_service = TsuruAPIService.new(
      logger: @logger,
      api_client: api_client,
      tsuru_home: @tsuru_home
    )

    team_users = api_service.create_teams_and_users(
      team_count: team_count,
      users_per_team: users_per_team
    )

    deploy_client = TsuruDeployClient.new(
      api_client: api_client,
      logger: @logger,
      environment: environment,
      host: host_suffix,
      tsuru_home: @tsuru_home
    )

    ###############
    # Deploy apps #
    ###############

    apps = [
      "example-java-jetty",
      "flask-sqlalchemy-postgres-heroku-example",
      # "multicloud-digitalmarketplace-search-api",
      "multicloud-digitalmarketplace-api",
      "multicloud-digitalmarketplace-supplier-frontend",
      "multicloud-digitalmarketplace-buyer-frontend",
      "multicloud-digitalmarketplace-admin-frontend"
    ]

    for app in apps
      @logger.info("Cloning https://github.com/alphagov/#{app} to #{@tsuru_home}/#{app}")
      unless File.exist? File.join(@tsuru_home, app)
        if !system("git clone https://github.com/alphagov/#{app} #{@tsuru_home}/#{app}")
          raise "Failed to clone the repo"
        end
      else
        if !system("cd #{@tsuru_home}/#{app} && git pull")
          raise "Failed to pull the lates changes"
        end
      end
    end

    log_dict = {}

    begin
      team_users.each do |team, users_in_team|
        log_dict[team] = {}
        ################### Deploy Java app ###################
        java_app_name = "java-app-" + Time.now.to_i.to_s.reverse
        log_dict[team][users_in_team[0][:email]] = {
          :app => java_app_name
        }
        deploy_client.deploy_app(
          user: users_in_team[0],
          app: {
            name: java_app_name,
            dir:  File.join(@tsuru_home, "example-java-jetty", "target"),
            platform: "java"
          },
          units: units_per_app
        )

        ################### Deploy Flask app ###################
        flask_app_name = "flask-app-" + Time.now.to_i.to_s.reverse
        # Generate a random DB instance. postgresql truncates this name
        # to create objects in postgres, so we need to keep the most variable
        # part in the first characters.
        flask_service_name = "db-" + Time.now.to_i.to_s.reverse
        log_dict[team][users_in_team[1][:email]] = {
          :app => flask_app_name,
          :service => flask_service_name
        }
        deploy_client.deploy_app(
          user: users_in_team[1],
          app: {
            name: flask_app_name,
            dir: File.join(@tsuru_home, "flask-sqlalchemy-postgres-heroku-example"),
            platform: "python"
          },
          postgres: flask_service_name,
          git: true,
          units: units_per_app
        )

        # ################### Deploy Digital Marketplace Search API backend ###################
        # dm_search_api_app_name = "dm-search-api-app-" + Time.now.to_i.to_s.reverse
        # dm_search_api_service_name = "es-" + Time.now.to_i.to_s.reverse
        # log_dict[team][users_in_team[2][:email]] = {
        #   :app => dm_api_app_name,
        #   :service => dm_api_service_name
        # }
        # deploy_client.deploy_app(
        #   user: users_in_team[2],
        #   app: {
        #     name: dm_api_app_name,
        #     dir: dm_api_app_dir,
        #     platform: "python"
        #   },
        #   env_vars: {
        #     DM_SEARCH_API_AUTH_TOKENS: search_api_token,
        #   },
        #   units: units_per_app
        # )

        ################### Deploy Digital Marketplace API backend ###################
        dm_api_app_name = "dm-api-app-" + Time.now.to_i.to_s.reverse
        dm_api_service_name = "db-" + Time.now.to_i.to_s.reverse
        log_dict[team][users_in_team[3][:email]] = {
          :app => dm_api_app_name,
          :service => dm_api_service_name
        }
        deploy_client.deploy_app(
          user: users_in_team[3],
          app: {
            name: dm_api_app_name,
            dir: File.join(@tsuru_home, "multicloud-digitalmarketplace-api"),
            platform: "python"
          },
          env_vars: {
            DM_API_AUTH_TOKENS: api_token,
            DM_SEARCH_API_AUTH_TOKEN: search_api_token,
            DM_SEARCH_API_URL: "https://preview-search-api.development.digitalmarketplace.service.gov.uk"
          },
          units: units_per_app,
          postgres: dm_api_service_name,
        )

        deploy_client.import_pg_dump(
          dm_api_app_name,
          dm_api_service_name,
          ssh_config
        )

        api_url = "https://" + api_client.get_app_url(dm_api_app_name)

        ################### Deploy Digital Marketplace Supplier frontend app ###################
        dm_supplier_frontend_app_name = "dm-supplier-frontend-app-" \
        + Time.now.to_i.to_s.reverse
        log_dict[team][users_in_team[4][:email]] = {
          :app => dm_supplier_frontend_app_name
        }
        deploy_client.deploy_app(
          user: users_in_team[4],
          app: {
            name: dm_supplier_frontend_app_name,
            dir: File.join(@tsuru_home, "multicloud-digitalmarketplace-supplier-frontend"),
            platform: "python"
          },
          env_vars: {
            DM_ADMIN_FRONTEND_COOKIE_SECRET: "secret",
            DM_ADMIN_FRONTEND_PASSWORD_HASH: "JHA1azIkMjcxMCRiNWZmMjhmMmExYTM0OGMyYTY0MjA3ZWFkOTIwNGM3NiQ4OGRLTHBUTWJQUE95UEVvSmg3djZYY2tWQ3lpcTZtaw==",
            DM_DATA_API_AUTH_TOKEN: api_token,
            DM_DATA_API_URL: api_url,
            DM_MANDRILL_API_KEY: "somekey",
            DM_PASSWORD_SECRET_KEY: "verySecretKey",
            DM_S3_DOCUMENT_BUCKET: "admin-frontend-dev-documents",
            DM_SEARCH_API_AUTH_TOKEN: search_api_token,
            DM_SEARCH_API_URL: "https://preview-search-api.development.digitalmarketplace.service.gov.uk"
          },
          units: units_per_app
        )

        ################### Deploy Digital Marketplace Buyer frontend app ###################
        dm_buyer_frontend_app_name = "dm-buyer-frontend-app-" \
        + Time.now.to_i.to_s.reverse
        log_dict[team][users_in_team[5][:email]] = {
          :app => dm_buyer_frontend_app_name
        }
        deploy_client.deploy_app(
          user: users_in_team[5],
          app: {
            name: dm_buyer_frontend_app_name,
            dir: File.join(@tsuru_home, "multicloud-digitalmarketplace-buyer-frontend"),
            platform: "python"
          },
          env_vars: {
            DM_ADMIN_FRONTEND_COOKIE_SECRET: "secret",
            DM_ADMIN_FRONTEND_PASSWORD_HASH: "JHA1azIkMjcxMCRiNWZmMjhmMmExYTM0OGMyYTY0MjA3ZWFkOTIwNGM3NiQ4OGRLTHBUTWJQUE95UEVvSmg3djZYY2tWQ3lpcTZtaw==",
            DM_DATA_API_AUTH_TOKEN: api_token,
            DM_DATA_API_URL: api_url,
            DM_S3_DOCUMENT_BUCKET: "admin-frontend-dev-documents",
            DM_SEARCH_API_AUTH_TOKEN: search_api_token,
            DM_SEARCH_API_URL: "https://preview-search-api.development.digitalmarketplace.service.gov.uk"
          },
          units: units_per_app
        )

        ################### Deploy Digital Marketplace Admin frontend app ###################
        dm_admin_frontend_app_name = "dm-admin-frontend-app-" \
        + Time.now.to_i.to_s.reverse
        log_dict[team][users_in_team[6][:email]] = {
          :app => dm_admin_frontend_app_name
        }
        deploy_client.deploy_app(
          user: users_in_team[6],
          app: {
            name: dm_admin_frontend_app_name,
            dir: File.join(@tsuru_home, "multicloud-digitalmarketplace-admin-frontend"),
            platform: "python"
          },
          env_vars: {
            DM_ADMIN_FRONTEND_COOKIE_SECRET: "secret",
            DM_ADMIN_FRONTEND_PASSWORD_HASH: "JHA1azIkMjcxMCRiNWZmMjhmMmExYTM0OGMyYTY0MjA3ZWFkOTIwNGM3NiQ4OGRLTHBUTWJQUE95UEVvSmg3djZYY2tWQ3lpcTZtaw==",
            DM_DATA_API_AUTH_TOKEN: api_token,
            DM_DATA_API_URL: api_url,
            DM_S3_DOCUMENT_BUCKET: "admin-frontend-dev-documents",
            DM_SEARCH_API_AUTH_TOKEN: search_api_token,
            DM_SEARCH_API_URL: "https://preview-search-api.development.digitalmarketplace.service.gov.uk"
          },
          units: units_per_app
        )

      end

    ensure
      state_string = YAML.dump(log_dict)
      @logger.info("Write state file #{state_file}")
      File.open(state_file, 'w') { |file| file.write(state_string) }
    end

  ensure
    FileUtils.remove_entry @tsuru_home
  end

  def destroy()
    environment    = @options[:environment]
    host_suffix    = @options[:host_suffix]
    state_file     = @options[:state_file]

    unless File.readable? state_file and File.file? state_file
      raise "Cannot read state file #{state_file}"
    end

    yaml_string = ''
    File.open(state_file, 'r') { |file| yaml_string = file.read }

    state = YAML.load(yaml_string)

    api_client = TsuruAPIClient.new(
        logger: @logger,
        environment: environment,
        host: host_suffix
    )


    @logger.info "Login admin user"
    api_client.login('administrator@gds.tsuru.gov', 'admin123')

    state.each do |team, users_in_team|
      @logger.info "Cleaning team #{team}"
      users_in_team.each do |user, deployed|
        if deployed.has_key?(:service)
          @logger.debug "Unbind service #{deployed[:service]}"
          begin
            api_client.unbind_service_from_app deployed[:service], deployed[:app]
          rescue Exception => e
            @logger.error "Cannot unbind service #{deployed[:service]} from #{deployed[:app]}. Exception: #{e}"
          end

          @logger.info "Remove service #{deployed[:service]}"
          begin
            api_client.remove_service_instance(deployed[:service])
          rescue Exception => e
            @logger.error "Cannot remove service #{deployed[:service]}. Exception: #{e}"
          end
        end
        @logger.debug "Remove application #{deployed[:app]}"
        begin
          api_client.remove_app deployed[:app]
        rescue Exception => e
          @logger.error "Cannot remove application #{deployed[:app]}. Exception: #{e}"
        end

        # Tsuru deletes the application in the background
        app_removed = false
        i = 0
        until app_removed or i == 60
          @logger.debug "Waiting for application #{deployed[:app]} to be deleted"
          sleep 1
          i += 1
          begin
            api_client.get_app_info deployed[:app]
          rescue Exception => e
            app_removed = true
          end
        end
        @logger.error "Application #{deployed[:app]} was not deleted in 60s" if i == 60

        @logger.debug "Remove user #{user}"
        begin
          api_client.remove_user user
        rescue Exception => e
          @logger.error "Cannot remove user #{user}. Exception: #{e}"
        end
    end
      @logger.debug "Remove team #{team}"
      failed = 0
      begin
        api_client.remove_team team
      rescue Exception => e
        @logger.error "Cannot remove team #{team}. Exception: #{e}"
        # Implemented retry because the team cannot be deleted immediately after deleting the apps
        if ! e.message.include? "404 Not Found" and failed < 3
          @logger.error "Retry to remove team #{team}"
          sleep 1
          failed += 1
          retry
        else
          @logger.error "Gave up removing team #{team}"
        end
      end

    end
  end

end
