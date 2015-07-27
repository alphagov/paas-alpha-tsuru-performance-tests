require 'tempfile'
require 'fileutils'
require 'command_line_helper'

# Ruby 2.2.2 does not provide mktmpdir. Use Tempfile instead
class Tempdir < Tempfile
  def initialize(basename)
    super
    File.delete(self.path)
    Dir.mkdir(self.path)
  end
  def rmrf
    FileUtils.rm_rf(@tmpname)
  end
  def unlink # copied from tempfile.rb
    # keep this order for thread safeness
    begin
      Dir.unlink(@tmpname) if File.exist?(@tmpname)
      @@cleanlist.delete(@tmpname)
      @data = @tmpname = nil
      ObjectSpace.undefine_finalizer(self)
    rescue Errno::EACCES
      # may not be able to unlink on Windows; just ignore
    end
  end
end

# Wrapper adount the TsuruCommandLine
class TsuruCommandLine < CommandLineHelper

  def target_add(target_label, target_url)
    execute_helper('tsuru', 'target-add', target_label, target_url)
  end

  def target_set(target_label)
    execute_helper('tsuru', 'target-set', target_label)
  end

  def target_list()
    execute_helper('tsuru', 'target-list')
  end

  def target_remove(target_label)
    execute_helper('tsuru', 'target-remove', target_label)
  end

  def app_create(app_name, platform)
    execute_helper('tsuru', 'app-create', app_name, platform, '-t', 'admin')
  end

  def app_remove(app_name)
    execute_helper('tsuru', 'app-remove', '-a', app_name, '-y')
  end

  def app_run(app_name, cmd)
    execute_helper('tsuru', 'app-run', '-a', app_name, cmd)
  end

  def app_run_once(app_name, cmd)
    execute_helper('tsuru', 'app-run', '-o', '-a', app_name, cmd)
  end

  def app_deploy(app_name, path, glob='*')
    cmd = ['tsuru', 'app-deploy']
    # Resolve the glob and make it relative to path
    cmd += Dir.glob(File.join(path, glob)).map{ |f| f.gsub(/#{path}\/*/, './') }
    cmd += ['-a', app_name]
    execute_helper(*cmd, { :chdir => path })
  end

  def app_unlock(app_name)
    execute_helper('tsuru-admin', 'app-unlock', '-a', app_name, '-y')
  end

  def key_add(ssh_key_name, ssh_key_path)
    execute_helper('tsuru', 'key-add', ssh_key_name, ssh_key_path)
  end

  def key_remove(ssh_key_name)
    execute_helper('tsuru', 'key-remove', ssh_key_name, '-y')
  end

  def service_add(service_name, service_instance_name, plan)
    execute_helper('tsuru', 'service-add', service_name, service_instance_name, plan, '-t', 'admin')
  end

  def service_remove(service_instance_name)
    execute_helper('tsuru', 'service-remove', service_instance_name, '-y')
  end

  def service_bind(service_instance_name, app_name)
    execute_helper('tsuru', 'service-bind', service_instance_name, '-a', app_name)
  end

  def service_unbind(service_instance_name, app_name)
    execute_helper('tsuru', 'service-unbind', service_instance_name, '-a', app_name)
  end

  def platform_add(platform_name, dockerfile)
    execute_helper('tsuru-admin', 'platform-add', platform_name, '-d', dockerfile)
  end

  def platform_remove(platform_name)
    execute_helper('tsuru-admin', 'platform-remove', platform_name, '-y')
  end

  def get_app_repository(app_name)
    execute_helper('tsuru', 'app-info', '-a', app_name)
    (m = /^Repository: (.*)$/.match(@stdout)) ? m[1] : nil
  end

  def tail_app_logs(app_name)
    execute_helper_async('tsuru','app-log','-a', app_name, '-f')
  end

  def get_app_address(app_name)
    execute_helper('tsuru', 'app-info', '-a', app_name)
    (m = /^Address: (.*)$/.match(@stdout)) ? m[1] : nil
  end

  def login(login, pass)
    execute_helper('tsuru', 'login', login) do |stdin, out, err, wait_thread|
      stdin.write(pass + "\n")
      stdin.flush()
      stdin.close()
    end
  end

end
