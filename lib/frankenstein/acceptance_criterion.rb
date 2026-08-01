# frozen_string_literal: true

module Frankenstein
  # A single statement that must remain true for a repository, together with
  # how it is proven (specification section 09). The acting agent may attempt
  # the work but may never grade itself, so a criterion names an *evaluator*
  # rather than trusting a self-reported result.
  class AcceptanceCriterion
    # Effect on review and autonomy. Changes to verifier definitions, security
    # posture, protected paths, or merge authority are :elevated and receive
    # extra scrutiny even when technically allowed.
    RISK_CLASSES = %i[low normal elevated].freeze

    # @return [Symbol] stable identity used in reports and history
    attr_reader :id
    # @return [String] human-readable statement of what must remain true
    attr_reader :claim
    # @return [Symbol] native evaluator name, GitHub check, or :command
    attr_reader :evaluator
    # @return [String, nil] the command to run when evaluator is :command
    attr_reader :run
    # @return [String, nil] target for evaluators that need one (e.g. /up)
    attr_reader :target
    # @return [Boolean] whether failure blocks advancement
    attr_reader :required
    # @return [Hash] supported environment, paths, services, or family scope
    attr_reader :scope
    # @return [String, nil] how recently evidence must have been produced
    attr_reader :freshness
    # @return [String] who may change or waive the criterion
    attr_reader :owner
    # @return [Symbol] one of {RISK_CLASSES}
    attr_reader :risk_class
    # @return [Provenance, nil] where this criterion came from, when discovered
    attr_reader :provenance

    def initialize(id:, claim:, evaluator:, run: nil, target: nil, required: true,
      scope: {}, freshness: nil, owner: "repository", risk_class: :normal, provenance: nil)
      @id = id.to_sym
      @claim = claim
      @evaluator = evaluator.to_sym
      @run = run
      @target = target
      @required = required
      @scope = scope
      @freshness = freshness
      @owner = owner
      @risk_class = risk_class.to_sym
      unless RISK_CLASSES.include?(@risk_class)
        raise UnknownError, "Unknown risk class #{risk_class.inspect}. Known: #{RISK_CLASSES.join(", ")}."
      end
      @provenance = provenance
    end

    def required? = @required

    # Verifier and contract-touching criteria carry elevated risk by policy.
    def elevated? = risk_class == :elevated

    def to_h
      {
        id: id,
        claim: claim,
        evaluator: evaluator,
        run: run,
        target: target,
        required: required,
        scope: scope,
        freshness: freshness,
        owner: owner,
        risk_class: risk_class
      }.compact
    end
  end
end
