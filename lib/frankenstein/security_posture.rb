# frozen_string_literal: true

module Frankenstein
  # The security posture presets from specification section 12. Security is
  # part of onboarding, not a hidden settings page, so the posture is a
  # first-class, named value with plain-language behavior - never a bundle of
  # silent relaxations.
  class SecurityPosture
    PRESETS = {
      strict: "Approved providers only, deny-by-default network and secrets, " \
              "protected workflows, no auto-merge, enhanced review for verifier changes.",
      balanced: "Approved package-registry network, hosted agents allowed, " \
                "patch submission permitted, no major automatic repair.",
      local: "Code and execution remain on user-controlled runners; external providers excluded.",
      custom: "Explicit controls with no hidden relaxation from a preset."
    }.freeze

    # What each posture makes mandatory (section 12). The posture - not the
    # project's shape - decides how much security proof a repository must show,
    # so the same gem is advisory under :balanced and blocking under :strict.
    # A control absent from a posture's map is not asked for at all.
    #
    # :local requires secret scanning because committed secrets are the one
    # risk that does not care whether the runner is yours. :custom implies
    # nothing: "no hidden relaxation from a preset" cuts both ways, so the
    # owner declares the controls they want and Frankenstein adds none.
    OBLIGATIONS = {
      strict: {
        security_policy: true, dependency_review: true, secret_scanning: true,
        static_analysis: false, ownership: false
      },
      balanced: {dependency_review: false, secret_scanning: false, security_policy: false},
      local: {secret_scanning: true, dependency_review: false},
      custom: {}
    }.freeze

    attr_reader :name

    def initialize(name)
      @name = name.to_sym
      unless PRESETS.key?(@name)
        raise UnknownError, "Unknown security posture #{name.inspect}. Known: #{PRESETS.keys.join(", ")}."
      end
      freeze
    end

    def self.[](name) = new(name)

    # Section 20 v1 default: balanced for public repositories, strict for
    # private repositories unless changed.
    def self.default_for(visibility)
      (visibility.to_s == "private") ? new(:strict) : new(:balanced)
    end

    def description = PRESETS.fetch(name)

    # Network egress the posture permits by default.
    def network
      case name
      when :strict, :local then :deny
      when :balanced then :package_registries
      else :custom
      end
    end

    # @return [Hash{Symbol=>Boolean}] security control id => whether a missing
    #   control blocks advancement under this posture
    def obligations = OBLIGATIONS.fetch(name)

    # @return [Array<Symbol>] controls whose absence blocks
    def required_controls = obligations.select { |_, required| required }.keys

    # @return [Array<Symbol>] controls reported but not blocking
    def advisory_controls = obligations.reject { |_, required| required }.keys

    def to_sym = name

    def to_s = name.to_s
  end
end
