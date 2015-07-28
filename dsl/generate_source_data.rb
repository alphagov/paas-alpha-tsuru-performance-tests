require 'logger'
require 'optparse'
require_relative '../bulk_deploy/tsuru_api_client'

options = {}
options[:log_level] = 'info'

parser = OptionParser.new do |opts|
  script_name = File.basename($0)
  opts.banner = "Usage: bundle exec #{script_name} [options]"
  opts.define_head "Example: bundle exec #{script_name} --environment perf-env --host-suffix tsuru2.paas.alphagov.co.uk"

  opts.on("-e", "--environment=e", "Environment [Required]") do |e|
    options[:environment] = e
  end
  opts.on("-h", "--host-suffix=h", "Host suffix [Required]") do |h|
    options[:host_suffix] = h
  end
  opts.on("-l", "--log-level=l", "Log level [Default: #{options[:log_level]}]") do |l|
    options[:log_level] = l
  end
end

begin
  parser.parse!
  raise "Error: Missing option: environment" unless options[:environment]
  raise "Error: Missing option: host_suffix" unless options[:host_suffix]
  raise "Error: Unknown log level: #{options[:log_level]}" unless
    ['debug', 'info', 'warn', 'error', 'fatal'].include? options[:log_level]
rescue Exception => e
  puts e
  puts parser
  exit 1
end

environment = options[:environment]
host_suffix = options[:host_suffix]

logger = Logger.new(STDOUT)
case options[:log_level].downcase
  when 'debug'
    logger.level = Logger::DEBUG
  when 'info'
    logger.level = Logger::INFO
  when 'warn'
    logger.level = Logger::WARN
  when 'error'
    logger.level = Logger::ERROR
  when 'fatal'
    logger.level = Logger::FATAL
  else
    raise "Error: Unknown log level: #{options[:log_level]}"
end

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


gov_paths = []
File.open("gov_uk_paths.txt", "r") do |f|
  gov_paths = f.readlines.each {|l| l.chomp!}
end


dm_buyer_paths = []
File.open("dm_buyer_paths.txt", "r") do |f|
  dm_buyer_paths = f.readlines.each {|l| l.chomp!}
end


AppType.dns_suffix = "#{environment}-hipache.#{host_suffix}"

app_types = []
app_types << AppType.new('java', 'java-app-')
app_types << AppType.new('flask', 'flask-app-')
app_types << AppType.new('gov_uk', 'gov-uk-', gov_paths)
app_types << AppType.new('dm-supplier-frontend', 'dm-supplier-frontend-app-', ['/suppliers'])
app_types << AppType.new('dm-buyer-frontend', 'dm-buyer-frontend-app-', dm_buyer_paths)
app_types << AppType.new('dm-admin-frontend', 'dm-admin-frontend-app-', ['/admin'])
app_types << AppType.new('dm-search-api', 'dm-search-api-app-')
app_types << AppType.new('dm-api', 'dm-api-app-')
app_types << AppType.new('gov-frontend', 'gov-frontend-')


api_client = TsuruAPIClient.new(
  logger: logger,
  environment: environment,
  host: host_suffix
)

logger.info("Connect to API [Environment: #{environment}, Host_suffix: #{host_suffix}]")
api_client.login 'administrator@gds.tsuru.gov', 'admin123'

logger.info("Get list of applications")
apps = api_client.list_apps

logger.info("Found #{apps.size} applications")

logger.info("Sort applications")
apps.each do |app|
    match = app_types.find { |t| /#{t.pattern}/ =~ app }
    next unless match
    logger.debug "Add application #{app} to type #{match.name}"
    match.add_app app
end


app_types.each do |app_type|
    file_name = "#{app_type.name}-apps.csv"
    urls = app_type.urls
    logger.info("Write #{urls.size} URLs to file #{file_name}")
    File.open(file_name, 'w') { |f| f.write urls * "\n" }
end

