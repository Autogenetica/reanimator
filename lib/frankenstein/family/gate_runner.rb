# frozen_string_literal: true

module Frankenstein
  class Family
    # Evaluates a family's gates (specification section 10). A candidate change
    # upstream can trigger downstream checks "without opening changes in
    # downstream repositories", so every check runs read-only, bounded, and in
    # a disposable copy of the downstream member - never in its working tree.
    #
    # Execution is opt-in exactly as it is for a baseline: by default the runner
    # reports what it *would* prove, so the graph is useful before anyone grants
    # the right to run anything.
    class GateRunner
      # A downstream member proves itself with its smoke script when it has one
      # (the section 10 example uses bin/smoke), else its discovered tests.
      SMOKE_SCRIPTS = ["bin/smoke", "bin/doctor", "script/smoke"].freeze

      attr_reader :family, :execute, :timeout

      def initialize(family, execute: false, timeout: nil)
        @family = family
        @execute = execute
        @timeout = timeout || Frankenstein.configuration.command_timeout
      end

      # @return [Array<GateResult>]
      def run
        family.gates.map { |gate| evaluate(gate) }
      end

      private

      def evaluate(gate)
        member = family.member(gate.requires_repository)
        return missing(gate, "#{gate.requires_repository} is not a member of family #{family.id}.") unless member
        return missing(gate, "No local checkout known for #{gate.requires_repository}.") unless member.path

        check = gate.check || discover_check(member)
        return missing(gate, "No proof command found in #{gate.requires_repository}; the edge is unverifiable.") unless check

        return planned(gate, check) unless execution_allowed?

        run_check(gate, member, check)
      end

      def run_check(gate, member, check)
        outcome = Isolation.copy(member.path) do |workspace|
          BoundedCommand.run(check, chdir: workspace, timeout: timeout)
        end

        if outcome.success?
          result(gate, :verified, detail: "#{check} passed in #{member.full_name}.", duration: outcome.duration)
        else
          reason = outcome.timed_out? ? "timed out after #{timeout}s" : "failed"
          result(gate, :failed, detail: "#{check} #{reason} in #{member.full_name}.", duration: outcome.duration)
        end
      end

      # The downstream member's own proof command: a smoke script if present,
      # otherwise whatever discovery says it runs for tests.
      def discover_check(member)
        repository = Repository.at(member.path)
        smoke = SMOKE_SCRIPTS.find { |script| repository.exist?(script) }
        return smoke if smoke

        Discovery.new(repository).run.discovered_commands[:tests]
      rescue RepositoryError
        nil
      end

      def execution_allowed?
        execute && Frankenstein.configuration.allow_execution
      end

      def planned(gate, check)
        result(gate, :planned, detail: "Would run #{check} in #{gate.requires_repository}.")
      end

      def missing(gate, detail)
        result(gate, :missing_evidence, detail: detail)
      end

      def result(gate, status, detail: nil, duration: nil)
        GateResult.new(
          gate: gate, status: status, detail: detail, duration: duration,
          relationship: family.relationship_between(gate.on, gate.requires_repository)
        )
      end
    end
  end
end
