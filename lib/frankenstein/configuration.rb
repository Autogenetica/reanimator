# frozen_string_literal: true

module Frankenstein
  # Process-wide configuration. Everything here has a safe, quiet default so
  # the library is useful with zero setup - configuration is for tightening,
  # not for enabling basic behavior.
  class Configuration
    # The file a repository owner may commit to declare intent and overrides.
    DEFAULT_CONTRACT_FILENAME = ".frankenstein.yml"

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
      @security_posture = (ENV["FRANKENSTEIN_SECURITY_POSTURE"] || "balanced").to_sym
      @contract_filename = ENV["FRANKENSTEIN_CONTRACT_FILE"] || DEFAULT_CONTRACT_FILENAME
      @command_timeout = Integer(ENV["FRANKENSTEIN_COMMAND_TIMEOUT"] || 900)
      @allow_execution = ENV["FRANKENSTEIN_ALLOW_EXECUTION"] != "false"
    end
  end
end
