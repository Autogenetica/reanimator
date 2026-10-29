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
  # It refuses to start while the submission token is in this process's
  # environment (see {.refuse_while_holding_token}).
  #
  # An optional argv prefix wraps the shell - {EgressControl} uses it to run
  # the command inside an empty network namespace.
  module BoundedCommand
    # Cap on captured output so a runaway producer cannot exhaust memory before
    # the time bound fires. The pipe is still drained past the cap so the child
    # never blocks on a full pipe; only accumulation stops.
    MAX_OUTPUT_BYTES = 1 << 20 # 1 MiB
    READ_CHUNK = 16_384

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
    # @raise [PolicyViolation] while the submission token is in this process's
    #   environment
    def run(command, chdir:, timeout:, prefix: [])
      refuse_while_holding_token
      started = clock
      stdin, out_and_err, wait_thread = Open3.popen2e(*prefix, "sh", "-c", command, chdir: chdir, pgroup: true)
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

    # Commands run repository code, which is untrusted, as the same user. Hiding
    # the token from the child is not enough: the child can read this
    # process's environment (ps eww, /proc/<pid>/environ), and unsetting a
    # variable does not erase the original environment block. So a process
    # holding the submission token never runs repository code at all - only
    # `reanimator submit`, which runs none, should be given it.
    def refuse_while_holding_token
      return if ENV[Configuration::GITHUB_TOKEN_ENV].to_s.empty?

      raise PolicyViolation,
        "#{Configuration::GITHUB_TOKEN_ENV} is set, and this would run repository code in the same process. " \
        "Unset it here; only `reanimator submit`, which runs no repository code, needs it."
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
