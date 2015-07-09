require 'logger'
require 'optparse'
require_relative 'deploy_actions'

options = {}
# Default values
options[:team_count] = 2
options[:users_per_team] = 7
options[:apps_per_team] = 5
options[:log_level] = 'info'
options[:units_per_app] = 3
options[:state_file] = File.expand_path(File.dirname($0) + '/deploy.state')
help = false

parser = OptionParser.new do |opts|
  script_name = File.basename($0)
  opts.banner = "Usage: bundle exec #{script_name} action [options]"
  opts.define_head "Example: bundle exec #{script_name} --environment perf-env --host-suffix tsuru2.paas.alphagov.co.uk apply"

  opts.on("-e", "--environment=e", "Environment [Required]") do |e|
    options[:environment] = e
  end
  opts.on("-h", "--host-suffix=h", "Host suffix [Required]") do |h|
    options[:host_suffix] = h
  end
  opts.on("-t", "--team-count=t", Integer, "Team count [Default: #{options[:team_count]}]") do |t|
    options[:team_count] = t
  end
  opts.on("-u", "--users-per-team=u", Integer, "Users per team [Default: #{options[:users_per_team]}]") do |u|
    options[:users_per_team] = u
  end
  opts.on("-a", "--apps-per-team=a", Integer, "Applications per team [Default: #{options[:apps_per_team]}]") do |a|
    options[:apps_per_team] = a
  end
  opts.on("-l", "--log-level=l", "Log level [Default: #{options[:log_level]}]") do |l|
    options[:log_level] = l
  end
  opts.on("-n", "--units_per_app=n", Integer, "Units per application [Default: #{options[:units_per_app]}]") do |n|
    options[:units_per_app] = n
  end
  opts.on("-s", "--state-file=f", "State file [Default: #{options[:state_file]}]") do |s|
    options[:state_file] = s
  end
end

begin
  parser.parse!
  raise "Error: Missing option: environment" unless options[:environment]
  raise "Error: Missing option: host_suffix" unless options[:host_suffix]
  unless options[:users_per_team] >= options[:apps_per_team]
    raise "Error: Number of users number must greater or equal to number of applications (#{options[:apps_per_team]})"
  end
  raise "Error: Unknown log level: #{options[:log_level]}" unless
    ['debug', 'info', 'warn', 'error', 'fatal'].include? options[:log_level]
rescue Exception => e
  puts e
  puts parser
  exit 1
end


if ARGV.size != 1
  puts parser
  exit 1
else
  action = ARGV[0]
end

deploy_actions = DeployActions.new(options)

case action
when 'apply'
  deploy_actions.apply
when 'destroy'
  deploy_actions.destroy
end

deploy_client = TsuruDeployClient.new(
    api_client: api_client,
    logger: logger,
    environment: environment,
    host: host_suffix,
    tsuru_home: tsuru_home
)

log_dict = {}

begin
  team_users.each do |team, users_in_team|
      log_dict[team] = []
      ################### Deploy Java app ###################
      java_app_name = "java-app-" + Time.now.to_i.to_s.reverse
      log_dict[team][0] = { :app => java_app_name }

      deploy_client.deploy_app(
          user: users_in_team[0],
          app: {
              name: java_app_name,
              dir: java_app_dir + "/target",
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
      log_dict[team][1] = { :app => flask_app_name, :service => flask_service_name }
      deploy_client.deploy_app(
          user: users_in_team[1],
          app: {
              name: flask_app_name,
              dir: flask_app_dir,
              platform: "python"
          },
          postgres: flask_service_name,
          git: true,
          units: units_per_app
      )

      ################### Deploy Digital Marketplace Supplier frontend app ###################
      dm_supplier_frontend_app_name = "dm-supplier-frontend-app-" \
      + Time.now.to_i.to_s.reverse
      log_dict[team][2] = { :app => dm_supplier_frontend_app_name }
      deploy_client.deploy_app(
          user: users[2],
          app: {
              name: dm_supplier_frontend_app_name,
              dir: dm_supplier_frontend_app_dir,
              platform: "python"
          },
          env_vars: {
              DM_ADMIN_FRONTEND_COOKIE_SECRET: "secret",
              DM_ADMIN_FRONTEND_PASSWORD_HASH: "JHA1azIkMjcxMCRiNWZmMjhmMmExYTM0OGMyYTY0MjA3ZWFkOTIwNGM3NiQ4OGRLTHBUTWJQUE95UEVvSmg3djZYY2tWQ3lpcTZtaw==",
              DM_DATA_API_AUTH_TOKEN: "wXeLg9vQNRqdkb9kccHDzFRaNL",
              DM_DATA_API_URL: "https://preview-api.development.digitalmarketplace.service.gov.uk",
              DM_MANDRILL_API_KEY: "somekey",
              DM_PASSWORD_SECRET_KEY: "verySecretKey",
              DM_S3_DOCUMENT_BUCKET: "admin-frontend-dev-documents",
              DM_SEARCH_API_AUTH_TOKEN: "CHbDLQtMvKoAuAtT8GM6vrdGGC",
              DM_SEARCH_API_URL: "https://preview-search-api.development.digitalmarketplace.service.gov.uk"
          },
          units: units_per_app
      )

      ################### Deploy Digital Marketplace Buyer frontend app ###################
      dm_buyer_frontend_app_name = "dm-buyer-frontend-app-" \
      + Time.now.to_i.to_s.reverse
      log_dict[team][3] = { :app => dm_buyer_frontend_app_name }
      deploy_client.deploy_app(
          user: users[3],
          app: {
              name: dm_buyer_frontend_app_name,
              dir: dm_buyer_frontend_app_dir,
              platform: "python"
          },
          env_vars: {
              DM_ADMIN_FRONTEND_COOKIE_SECRET: "secret",
              DM_ADMIN_FRONTEND_PASSWORD_HASH: "JHA1azIkMjcxMCRiNWZmMjhmMmExYTM0OGMyYTY0MjA3ZWFkOTIwNGM3NiQ4OGRLTHBUTWJQUE95UEVvSmg3djZYY2tWQ3lpcTZtaw==",
              DM_DATA_API_AUTH_TOKEN: "wXeLg9vQNRqdkb9kccHDzFRaNL",
              DM_DATA_API_URL: "https://preview-api.development.digitalmarketplace.service.gov.uk",
              DM_S3_DOCUMENT_BUCKET: "admin-frontend-dev-documents",
              DM_SEARCH_API_AUTH_TOKEN: "CHbDLQtMvKoAuAtT8GM6vrdGGC",
              DM_SEARCH_API_URL: "https://preview-search-api.development.digitalmarketplace.service.gov.uk"
          },
          units: units_per_app
      )

      ################### Deploy Digital Marketplace Admin frontend app ###################
      dm_admin_frontend_app_name = "dm-admin-frontend-app-" \
      + Time.now.to_i.to_s.reverse
      log_dict[team][4] = { :app => dm_admin_frontend_app_name }
      deploy_client.deploy_app(
          user: users[4],
          app: {
              name: dm_admin_frontend_app_name,
              dir: dm_admin_frontend_app_dir,
              platform: "python"
          },
          env_vars: {
              DM_ADMIN_FRONTEND_COOKIE_SECRET: "secret",
              DM_ADMIN_FRONTEND_PASSWORD_HASH: "JHA1azIkMjcxMCRiNWZmMjhmMmExYTM0OGMyYTY0MjA3ZWFkOTIwNGM3NiQ4OGRLTHBUTWJQUE95UEVvSmg3djZYY2tWQ3lpcTZtaw==",
              DM_DATA_API_AUTH_TOKEN: "wXeLg9vQNRqdkb9kccHDzFRaNL",
              DM_DATA_API_URL: "https://preview-api.development.digitalmarketplace.service.gov.uk",
              DM_S3_DOCUMENT_BUCKET: "admin-frontend-dev-documents",
              DM_SEARCH_API_AUTH_TOKEN: "CHbDLQtMvKoAuAtT8GM6vrdGGC",
              DM_SEARCH_API_URL: "https://preview-search-api.development.digitalmarketplace.service.gov.uk"
          },
          units: units_per_app
      )

  end

ensure
  state_string = YAML.dump(log_dict)
  logger.info("Write state file #{state_file}")
  File.open(state_file, 'w') { |file| file.write(state_string) }
end
