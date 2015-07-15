require 'logger'
require_relative '../bulk_deploy/tsuru_api_client'

environment = 'danjim'
host_suffix = 'tsuru2.paas.alphagov.co.uk'
logger = Logger.new(STDOUT)
logger.level = Logger::INFO

class AppType
  attr_accessor :name, :pattern, :paths, :apps
  def initialize(name, pattern, paths = nil)
    @name = name
    @pattern = pattern
    @paths = paths
    @apps = []
  end

  def self.dns_suffix=(dns_suffix)
    @@dns_suffix = dns_suffix
  end

  def add_app(app)
    @apps << app
  end

  def urls
    app_urls = []
    @apps.each{ |app|
      if @paths
        @paths.each { |path|
          app_urls << "http://#{app}.#{@@dns_suffix}#{path}"
        }
      else
        app_urls << "http://#{app}.#{@@dns_suffix}/"
      end
    }
    app_urls
  end

end

AppType.dns_suffix = "#{environment}-hipache.#{host_suffix}"

app_types = []
app_types << AppType.new('java', 'java-app-')
app_types << AppType.new('flask', 'flask-app-')
app_types << AppType.new('dm-supplier-frontend', 'dm-supplier-frontend-app-', ['/suppliers'])
app_types << AppType.new('dm-buyer-frontend', 'dm-buyer-frontend-app-', ['/'])
app_types << AppType.new('dm-admin-frontend', 'dm-admin-frontend-app-', ['/admin'])
app_types << AppType.new('dm-search-api', 'dm-search-api-app-', ['/'])
app_types << AppType.new('dm-api', 'dm-api-app-', ['/'])


api_client = TsuruAPIClient.new(
  logger: logger,
  environment: environment,
  host: host_suffix
)

api_client.login 'administrator@gds.tsuru.gov', 'admin123'

apps = api_client.list_apps

apps.each do |app|
    match = app_types.find { |d| /#{d.pattern}/ =~ app }
    next unless match
    match.add_app app
end

app_types.each do |app_type|
    File.open("#{app_type.name}.csv", 'w') { |f| f.write app_type.urls * "\n" }
end

