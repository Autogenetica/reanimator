# frozen_string_literal: true

module Reanimator
  # Evaluators turn an acceptance criterion into a {CriterionResult}. They are
  # the isolated grading half of section 09: the thing that decides pass or
  # fail is deliberately separate from anything that could edit the repository.
  #
  # Two families live here. *Native* evaluators (repository integrity,
  # documentation, support matrix, security evidence) read only inspection
  # data and always run,
  # even in the non-executing default - that is how a read-only baseline can
  # still prove something. *Command* and *smoke* evaluators represent work that
  # must actually execute, so they only run when a baseline is explicitly asked
  # to execute.
  module Evaluators
    module_function

    # @param criterion [AcceptanceCriterion]
    # @param contract [EffectiveContract]
    # @param execute [Boolean]
    # @param timeout [Integer]
    # @param execution_root [String] directory commands run in - a disposable
    #   copy when executing, so the original working tree is never touched
    # @return [Evaluators::Base]
    def for(criterion, contract:, execute:, timeout:, execution_root: contract.repository.path)
      klass = registry.fetch(criterion.evaluator, Unsupported)
      klass.new(criterion, contract: contract, execute: execute, timeout: timeout, execution_root: execution_root)
    end

    def registry
      {
        command: Command,
        http_smoke: HttpSmoke,
        repository_integrity: RepositoryIntegrity,
        documentation_check: DocumentationCheck,
        support_matrix: SupportMatrix,
        security_evidence: SecurityEvidence
      }
    end
  end
end
