require "ruby-jmeter"


require "rubygems"
require "ruby-jmeter"
require "cgi"

if ARGV.size != 4
  puts "------- Tsuru perf test: ERROR! --------"
  puts "      Usage:"
  puts "      Please specify a tsuru target env, tsuru root hostname"
  puts "      a thread count and a loop count for each thread.\n"
  puts "      Example:"
  puts "          bundle exec ruby cleanup_apps.rb ci tsuru2.paas.alphagov.co.uk 1 1"
  exit 1
end

environment  = ARGV[0]
environment_suffix  = ARGV[1]
thread_count = ARGV[2].to_i
loop_count   = ARGV[3].to_i


test do
  cookies
  csv_data_set_config filename: 'flask_apps.csv',
    variableNames: 'app_url'

  threads count: thread_count do
    visit name: 'home page', url: '${app_url}' do
   	  assert contains: "Flasktest"
  	end
  	visit name:"login", url: '${app_url}/login' do
  	  assert contains: "Password"
  	end
  	submit name: 'Submit Form', url: '${app_url}/login',
  		fill_in: {
    		username: 'admin',
    		password: 'default',
  		}

  	submit name: 'Add a blogpost', url: '${app_url}/add',
  		fill_in: {
  			title: "hola",
  			text: "This is not a test",
  		}
  	visit name: 'Capture for delete', url: '${app_url}' do
		extract regex: '/remove/(.+?)', variable: 'post_id' do
  			visit name: 'Delete posts', url: '${app_url}/remove/${post_id}'
  		end
  	end
  end


  csv_data_set_config filename: 'java_apps.csv',
  	variableNames: 'java_app_url'
  threads count: thread_count do
  	visit name: 'Java app home page', url: '${java_app_url}'
  		assert contains: "Powered by"
  end


end.jmx


