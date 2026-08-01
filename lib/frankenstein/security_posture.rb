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

    def to_sym = name

    def to_s = name.to_s
  end
end
