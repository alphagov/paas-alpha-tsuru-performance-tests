require 'logger'
require_relative '../bulk_deploy/tsuru_api_client'

environment = 'danjim'
host_suffix = 'tsuru2.paas.alphagov.co.uk'
logger = Logger.new(STDOUT)
logger.level = Logger::INFO

api_client = TsuruAPIClient.new(
  logger: logger,
  environment: environment,
  host: host_suffix
)

api_client.login 'administrator@gds.tsuru.gov', 'admin123'

apps = api_client.list_apps

patterns = ['java-app-', 'flask-app-', 'dm-supplier-frontend-app-', 'dm-buyer-frontend-app-',
            'dm-admin-frontend-app-', 'dm-search-api-app-', 'dm-api-app-']

sorted = {}

apps.each do |app|
    match = patterns.find { |p| /#{p}/ =~ app }
    next unless match
    sorted[match] = [] unless sorted.has_key? match
    sorted[match] << app
    sorted[match] << app
end

sorted.each do |pattern, apps|
    File.open("#{pattern}.csv", 'w') { |f| f.write apps * "\n" }
end

