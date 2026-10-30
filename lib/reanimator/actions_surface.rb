# frozen_string_literal: true

require "securerandom"

module Reanimator
  # Delivers findings to the place a human will see them in CI (section 16)
  # without platform work: inside GitHub Actions, annotations go to standard
  # output and a summary is appended to the job summary. Outside Actions it
  # prints reports plainly and publishes nothing - the exit status still
  # carries the signal.
  #
  # Reports quote repository-controlled text (criterion claims, details, run
  # reasons), and inside Actions any line starting with "::" is a workflow
  # command. So reports are printed between ::stop-commands:: markers with a
  # fresh token, and the summary's code fence is longer than any run of
  # backticks in it, so repository text can neither forge an annotation nor
  # switch the real ones off.
  module ActionsSurface
    module_function

    def active?(env = ENV) = env["GITHUB_ACTIONS"] == "true"

    # Prints a report whose text the repository partly controls.
    def print_report(text, env: ENV, out: $stdout)
      return out.puts(text) unless active?(env)

      token = SecureRandom.hex(16)
      out.puts("::stop-commands::#{token}", text, "::#{token}::")
    end

    # @param annotations [Array<String>] workflow-command lines
    # @param summaries [Array<Array(String, String)>] [heading, body] pairs
    def publish(annotations:, summaries:, env: ENV, out: $stdout, err: $stderr)
      return unless active?(env)

      annotations.each { |line| out.puts(line) }
      write_summary(summaries.map { |heading, body| section(heading, body) }.join("\n\n"), env, err)
    end

    def section(heading, body)
      fence = "`" * [3, body.scan(/`+/).map(&:size).max.to_i + 1].max
      "### #{heading.gsub(/[\r\n]+/, " ")}\n\n#{fence}\n#{body}\n#{fence}"
    end

    # A summary that cannot be written is reported, not raised: the findings
    # and exit status already carry the signal.
    def write_summary(text, env, err)
      path = env["GITHUB_STEP_SUMMARY"].to_s
      File.write(path, "#{text}\n", mode: "a") unless path.empty?
    rescue SystemCallError => e
      err.puts("reanimator: could not write the job summary (#{e.message})")
    end
  end
end
