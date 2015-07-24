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
  opts.define_head "Example: bundle exec #{script_name} -e perf-env -h tsuru2.paas.alphagov.co.uk -T ourtoken -S oursearchtoken apply"

  opts.on("-e", "--environment=e", "Environment [Required]") do |e|
    options[:environment] = e
  end
  opts.on("-h", "--host-suffix=h", "Host suffix [Required]") do |h|
    options[:host_suffix] = h
  end
  opts.on("-T", "--api-token=T", "API token [Required]") do |t|
    options[:api_token] = t
  end
  opts.on("-S", "--search-api-token=S", "Search API token [Required]") do |s|
    options[:search_api_token] = s
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

  if ARGV.size != 1
    puts parser
    exit 1
  else
    action = ARGV[0]
  end

  raise "Error: Missing option: environment" unless options[:environment]
  raise "Error: Missing option: host_suffix" unless options[:host_suffix]
  if action == "apply"
    # Tokens are only needed for apply action
    raise "Error: Missing option: api_token" unless options[:api_token]
    raise "Error: Missing option: search_api_token" unless options[:search_api_token]
  end
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

deploy_actions = DeployActions.new(options)

case action
when 'apply'
  deploy_actions.apply
when 'destroy'
  deploy_actions.destroy
end
