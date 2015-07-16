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

  # Flask
  threads count: thread_count, loops: loop_count do
    csv_data_set_config filename: 'flask.csv',
                        variableNames: 'flask_url'
    visit name: 'Flask app home page', url: '${flask_url}' do
      assert contains: "Flasktest"
    end
    visit name:"login", url: '${flask_url}/login' do
      assert contains: "Password"
    end
    submit name: 'Submit Form', url: '${flask_url}/login',
        fill_in: {
            username: 'admin',
            password: 'default',
        }

    submit name: 'Add a blogpost',
           url: '${flask_url}/add',
           fill_in: {
             title: 'hola',
             text: 'This is not a test',
           }
    visit name: 'Capture for delete', url: '${flask_url}' do
        extract regex: '/remove/(.+?)', variable: 'post_id' do
            visit name: 'Delete posts', url: '${flask_url}/remove/${post_id}'
        end
    end
  end

  # Java
  threads count: thread_count, loops: loop_count do
    csv_data_set_config filename: 'java.csv',
                        variableNames: 'java_url'
    visit name: 'Java app home page', url: '${java_url}'
    assert contains: 'Powered by'
  end

  # gov.uk
  threads count: thread_count, loops: loop_count do
    csv_data_set_config filename: 'gov_uk_urls.csv',
                        variableNames: 'g_url'
    visit name: 'Visiting ${g_url}', url: '${g_url}'
  end

  # Digital marketplace admin
  threads count: thread_count, loops: loop_count do
    csv_data_set_config filename: 'dm-admin-frontend.csv',
                        variableNames: 'dm_admin_url'
    visit name: 'Visiting ${dm_admin_url}', url: '${dm_admin_url}'
  end

  # Digital marketplace buyer
  threads count: thread_count, loops: loop_count do
    csv_data_set_config filename: 'dm-buyer-frontend.csv',
                        variableNames: 'dm_buyer_url'
    visit name: 'Visiting ${dm_buyer_url}', url: '${dm_buyer_url}'
  end

  # Digital marketplace supplier
  threads count: thread_count, loops: loop_count do
    csv_data_set_config filename: 'dm-supplier-frontend.csv',
                        variableNames: 'dm_supplier_url'
    visit name: 'Visiting ${dm_supplier_url}', url: '${dm_supplier_url}'
  end

  # # Digital marketplace API
  # threads count: thread_count, loops: loop_count do
  #   csv_data_set_config filename: 'dm-api.csv',
  #                       variableNames: 'dm_api_url'
  #   visit name: 'Visiting ${dm_api_url}', url: '${dm_api_url}'
  # end

  # # Digital marketplace Search API
  # threads count: thread_count, loops: loop_count do
  #   csv_data_set_config filename: 'dm-search-api.csv',
  #                       variableNames: 'dm_search_api_url'
  #   visit name: 'Visiting ${dm_search_api_url}', url: '${dm_search_api_url}'
  # end

  view_results_tree

end.jmx