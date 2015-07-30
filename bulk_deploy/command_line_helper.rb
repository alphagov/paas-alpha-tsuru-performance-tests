require 'open3'

# Generic wrapper around the CommandLine
class CommandLineHelper
  attr_reader :exit_status, :stderr, :stdout, :stdouterr, :last_command, :env
  attr_accessor :output_file

  def initialize(env = {}, options = {})
    @env = env
    @options = options
    @output_file = options[:output_file]
  end

  def wait()
    @tout.join if @tout
    @terr.join if @terr
    if @wait_thread
      # Return code can be the the signal number if killed with signal
      # or exit value shifted 8 bits if exited normally
      if @wait_thread.value.signaled?
        @exit_status = @wait_thread.value.to_i + 128
      else
        @exit_status = @wait_thread.value.to_i >> 8
      end
    end
    self
  end

  def ctrl_c()
    Process.kill("TERM", @wait_thread.pid)
  end

  protected

  def clear_run()
    @exit_status=nil
    @stderr = ''
    @stdout = ''
    @stdouterr = ''
  end

  def write_message(msg)
    $stdout.puts msg if @options[:verbose]
    @output_file.puts msg if (@output_file and not @output_file.closed?)
  end

  def write_stdout(l)
    $stdout.puts "stdout: #{l}" if @options[:verbose]
    @output_file.puts "stdout: #{l}" if (@output_file and not @output_file.closed?)
    @stdouterr << "stdout: #{l}"
    @stdout << l
  end

  def write_stderr(l)
    $stderr.puts "stderr: #{l}" if @options[:verbose]
    @output_file.puts "stderr: #{l}" if (@output_file and not @output_file.closed?)
    @stdouterr << "stderr: #{l}"
    @stderr << l
  end

  def execute_helper_async(*cmd)
    clear_run()
    executing_log = "Executing: #{@env.map { |k,v| "#{k}='#{v}'" }.join(' ')} #{cmd.join(' ')}"
    write_message(executing_log)

    @in_fd, @out_fd, @err_fd, @wait_thread = Open3.popen3(@env, *cmd)
    @in_fd.close if @options[:close_stdin]

    # Print standard out end error as they receive content
    @tout = Thread.new do
      @out_fd.each {|l| write_stdout(l) }
    end
    @terr = Thread.new do
      @err_fd.each {|l| write_stderr(l) }
    end
  end

  def execute_helper(*cmd)
    execute_helper_async(*cmd)

    # Allow additional preprocessing of the system call if the caller passes a block
    yield(@in_fd, @out_fd, @err_fd, @wait_thread) if block_given?

    self.wait

    write_message "Exit code: #{@exit_status}" if @options[:verbose]
    return @exit_status == 0
  end

end
