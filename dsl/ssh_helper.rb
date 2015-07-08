class SshHelper
  # Create our own SSH key
  def self.generate_key(path)
    FileUtils.mkdir_p(File.dirname(path))
    system("ssh-keygen -f #{path} -q -N '' ")
  end

  # Generate some custom configuration for SSH
  # WARNING: overrides the file
  def self.write_config(config_path, config)
    File.open(config_path, "w") do |f|
      f.write("Host *\n")
      config.each do |k, v|
        f.write("\t#{k} #{v}\n")
      end
    end
  end

  # Older versions of git < 2.3 do not allow use the GIT_SSH_COMMAND variable
  # but only specify the ssh binary with GIT_SSH. Because that, in order to
  # specify the configuration file we need to create a wrapper
  def self.write_ssh_wrapper(wrapper_path, config_path)
    File.open(wrapper_path, "w") do |f|
      f.write("""
#!/bin/bash
ssh -F #{config_path} $@
""")
    end
    File.chmod(0755, wrapper_path)
  end
end
