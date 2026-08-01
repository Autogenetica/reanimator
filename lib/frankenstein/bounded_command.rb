# frozen_string_literal: true

require "open3"
require "timeout"

module Frankenstein
  # Runs a single shell command under a hard wall-clock bound and captures its
  # combined output (specification section 12: bounded attempts, time, and
  # paths). Baselines are bounded by construction - a check that hangs is a
  # failed check, never an unbounded wait. The command runs in the repository
  # directory through `sh -c` so discovered commands with globs (for example
  # `gem build *.gemspec`) behave as they do in CI.
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
      stdin, out_and_err, wait_thread = Open3.popen2e("sh", "-c", command, chdir: chdir)
      stdin.close

      output = +""
      timed_out = false
      begin
        Timeout.timeout(timeout) { output << out_and_err.read }
        wait_thread.join
      rescue Timeout::Error
        timed_out = true
        kill(wait_thread.pid)
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

    def kill(pid)
      Process.kill("TERM", pid)
      Process.kill("KILL", pid)
    rescue Errno::ESRCH, Errno::EPERM
      # Already gone; nothing to clean up.
    end

    # Monotonic clock so a system time change cannot skew a duration.
    def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
