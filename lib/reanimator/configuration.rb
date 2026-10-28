# frozen_string_literal: true

module Reanimator
  # Process-wide configuration. Everything here has a safe, quiet default so
  # the library is useful with zero setup - configuration is for tightening,
  # not for enabling basic behavior.
  class Configuration
    # The file a repository owner may commit to declare intent and overrides.
    DEFAULT_CONTRACT_FILENAME = ".reanimator.yml"

    # The environment variable holding the token a {Submitter} uses to open
    # draft pull requests. Only the submitter reads it, and it is withheld from
    # every command a check executes - repository code is untrusted input.
    GITHUB_TOKEN_ENV = "REANIMATOR_GITHUB_TOKEN"

    # @return [Symbol] the security posture applied when a repository does not
    #   declare one (:strict, :balanced, :local, :custom). Section 20 sets
    #   :balanced for public repositories as the v1 default.
    attr_accessor :security_posture

    # @return [String] the filename scanned for a repository-owned contract.
    attr_accessor :contract_filename

    # @return [Integer] wall-clock ceiling, in seconds, for any single check
    #   executed during a baseline. Baselines are bounded by construction.
    attr_accessor :command_timeout

    # @return [Boolean] whether baseline checks may execute at all. Even when
    #   true, execution is opt-in per run; when false the runner only ever
    #   plans, never spawns a process.
    attr_accessor :allow_execution

    def initialize
      @security_posture = (ENV["REANIMATOR_SECURITY_POSTURE"] || "balanced").to_sym
      @contract_filename = ENV["REANIMATOR_CONTRACT_FILE"] || DEFAULT_CONTRACT_FILENAME
      @command_timeout = Integer(ENV["REANIMATOR_COMMAND_TIMEOUT"] || 900)
      @allow_execution = ENV["REANIMATOR_ALLOW_EXECUTION"] != "false"
    end

    # Execution is doubly gated: a run must ask for it and the configuration
    # must allow it.
    #
    # @param requested [Boolean] the per-run execute flag
    def execution_permitted?(requested) = requested && allow_execution
  end
end
