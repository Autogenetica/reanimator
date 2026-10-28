# frozen_string_literal: true

require "open3"
require "timeout"

module Reanimator
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
  #
  # An optional argv prefix wraps the shell - {EgressControl} uses it to run
  # the command inside an empty network namespace.
  module BoundedCommand
    # Cap on captured output so a runaway producer cannot exhaust memory before
    # the time bound fires. The pipe is still drained past the cap so the child
    # never blocks on a full pipe; only accumulation stops.
    MAX_OUTPUT_BYTES = 1 << 20 # 1 MiB
    READ_CHUNK = 16_384

    # Credentials the command must never see. Checks run repository code, which
    # is untrusted input, so a token held for submission stays with the
    # submitter.
    WITHHELD_ENV = {Configuration::GITHUB_TOKEN_ENV => nil}.freeze

    Result = Struct.new(:success, :output, :duration, :timed_out) do
      def success? = success
      def timed_out? = timed_out
    end

    module_function

    # @param command [String]
    # @param chdir [String]
    # @param timeout [Integer] seconds
    # @param prefix [Array<String>] argv run in front of `sh -c`
    # @return [Result]
    def run(command, chdir:, timeout:, prefix: [])
      started = clock
      stdin, out_and_err, wait_thread = Open3.popen2e(WITHHELD_ENV, *prefix, "sh", "-c", command, chdir: chdir, pgroup: true)
      stdin.close
      out_and_err.binmode

      output = +"".b
      truncated = false
      timed_out = false
      begin
        Timeout.timeout(timeout) do
          while (chunk = out_and_err.read(READ_CHUNK))
            if output.bytesize < MAX_OUTPUT_BYTES
              output << chunk
            else
              truncated = true # keep draining, stop accumulating
            end
          end
        end
        wait_thread.join
      rescue Timeout::Error
        timed_out = true
        kill_group(wait_thread.pid)
        wait_thread.join # reap the terminated leader
      ensure
        out_and_err.close
      end

      output << "\n...[output truncated]" if truncated

      Result.new(
        success: !timed_out && wait_thread.value&.success?,
        # Command output is untrusted bytes; present it as scrubbed UTF-8 so
        # callers' string operations never raise.
        output: output.force_encoding("UTF-8").scrub,
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
