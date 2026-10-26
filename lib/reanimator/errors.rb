# frozen_string_literal: true

module Reanimator
  # Base class for every error the library raises, so consumers can rescue the
  # whole family with a single `rescue Reanimator::Error`.
  class Error < StandardError; end

  # Raised when a path is not a usable repository root.
  class RepositoryError < Error; end

  # Raised when a .reanimator.yml (or an inline contract) fails validation.
  class ContractError < Error; end

  # Raised when a requested profile, intent, or evaluator is not registered.
  class UnknownError < Error; end

  # Raised when a policy layer attempts to loosen a constraint it may not
  # loosen - the precedence rules in section 07 of the specification are not
  # advisory, they are enforced.
  class PolicyViolation < Error; end
end
