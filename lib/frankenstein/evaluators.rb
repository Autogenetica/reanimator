# frozen_string_literal: true

module Frankenstein
  # Evaluators turn an acceptance criterion into a {CriterionResult}. They are
  # the isolated grading half of section 09: the thing that decides pass or
  # fail is deliberately separate from anything that could edit the repository.
  #
  # Two families live here. *Native* evaluators (repository integrity,
  # documentation, support matrix) read only inspection data and always run,
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
    # @return [Evaluators::Base]
    def for(criterion, contract:, execute:, timeout:)
      klass = registry.fetch(criterion.evaluator, Unsupported)
      klass.new(criterion, contract: contract, execute: execute, timeout: timeout)
    end

    def registry
      {
        command: Command,
        http_smoke: HttpSmoke,
        repository_integrity: RepositoryIntegrity,
        documentation_check: DocumentationCheck,
        support_matrix: SupportMatrix
      }
    end
  end
end
