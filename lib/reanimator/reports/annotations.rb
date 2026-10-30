# frozen_string_literal: true

module Reanimator
  module Reports
    # Renders findings as GitHub Actions workflow commands (section 16), so a
    # repository that needs a human surfaces on the run page and the pull
    # request without anyone reading a log. One annotation per finding:
    # blocking findings are errors, matching the exit status; advisory ones are
    # notices, which GitHub caps separately and shows with less weight.
    class Annotations
      LEVELS = {error: "error", notice: "notice"}.freeze

      # @param findings [Array<Finding>]
      def initialize(findings)
        @findings = findings
      end

      # @return [Array<String>]
      def render
        @findings.map do |finding|
          "::#{LEVELS.fetch(finding.level)} title=#{escape_property("Reanimator: #{finding.title}")}::" \
            "#{escape_data(finding.message)}"
        end
      end

      private

      # Workflow-command escaping: data loses %, CR and LF; properties also lose
      # the separators : and ,.
      def escape_data(text) = text.to_s.gsub("%", "%25").gsub("\r", "%0D").gsub("\n", "%0A")

      def escape_property(text) = escape_data(text).gsub(":", "%3A").gsub(",", "%2C")
    end
  end
end
