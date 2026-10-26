# frozen_string_literal: true

module Reanimator
  module Reports
    # Renders the resolved autonomy for a repository across every task class
    # (specification section 11). It shows how the conservative defaults, the
    # repository's enabled autonomy, and the safety floor combine into what an
    # agent may actually do - and flags where elevated review applies.
    class Permissions
      def initialize(contract)
        @contract = contract
        @model = PermissionModel.new(contract)
      end

      def render
        header = "Permissions — #{@contract.repository.full_name} " \
          "(autonomy: #{@contract.autonomy.map { |k, v| "#{k}=#{v}" }.join(" ")})"
        rows = TaskClass.keys.map { |key| row(TaskClass.fetch(key)) }
        [header, "", *rows].join("\n")
      end

      private

      def row(task_class)
        resolution = @model.resolve(task_class)
        actions = AutonomyLevel.keys.map { |level| "#{level}=#{resolution.actions[level]}" }.join(" ")
        elevated = resolution.elevated_review? ? "  [elevated review]" : ""
        "  #{task_class.title}: max=#{resolution.max_action} | #{actions}#{elevated}"
      end
    end
  end
end
