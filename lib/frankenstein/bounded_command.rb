# frozen_string_literal: true

require "open3"
require "timeout"

module Frankenstein
  # Runs a single shell command under a hard wall-clock bound and captures its
  # combined output (specification section 12: bounded attempts, time, and
  # paths). Baselines are bounded by construction - a check that hangs is a
  # failed check, never an unbounded wait. The command runs through `sh -c` so
  # discovered commands with globs (for example `gem build *.gemspec`) behave as
  # they do in CI.
  #
  # The child is started as its own process-group leader and, on timeout, the
  # *entire group* is signalled - not just the `sh` parent - so a spawned
  # grandchild (the actual test or build process) cannot outlive the bound.
  module BoundedCommand
    Result = Struct.new(:success, :output, :duration, :timed_out) do
      def success? = success
      def timed_out? = timed_out
    end

    module_function

    # @param command [String]
    # @param chdir [String]
    # @param timeout [Integer] seconds
    # @return [Result]
    def run(command, chdir:, timeout:)
      started = clock
      stdin, out_and_err, wait_thread = Open3.popen2e("sh", "-c", command, chdir: chdir, pgroup: true)
      stdin.close

      output = +""
      timed_out = false
      begin
        Timeout.timeout(timeout) { output << out_and_err.read }
        wait_thread.join
      rescue Timeout::Error
        timed_out = true
        kill_group(wait_thread.pid)
        wait_thread.join # reap the terminated leader
      ensure
        out_and_err.close
      end

      Result.new(
        success: !timed_out && wait_thread.value&.success?,
        output: output,
        duration: (clock - started).round(2),
        timed_out: timed_out
      )
    end

    # Signals the whole process group led by pid (the negative-pid form), so
    # every process the command spawned is terminated together.
    def kill_group(pid)
      Process.kill("TERM", -pid)
      Process.kill("KILL", -pid)
    rescue Errno::ESRCH, Errno::EPERM
      # Already gone; nothing to clean up.
    end

    # Monotonic clock so a system time change cannot skew a duration.
    def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
