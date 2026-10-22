# frozen_string_literal: true

module Frankenstein
  # A family of security evidence a posture can require (specification section
  # 12). Controls are named by *obligation* rather than by tool: "dependency
  # risk is reviewed" is satisfied by Dependabot, bundler-audit, or the
  # dependency-review action alike, so a repository that already solved the
  # problem its own way is credited rather than asked to adopt ours.
  class SecurityControl
    REGISTRY = {
      dependency_review: {
        claim: "Dependency risk is reviewed automatically.",
        satisfied_by: %i[dependabot security_dependency_review security_bundler_dependency_audit].freeze,
        remedy: "No dependency review found. Add .github/dependabot.yml, bundler-audit, or actions/dependency-review-action."
      },
      secret_scanning: {
        claim: "Committed secrets are scanned for.",
        satisfied_by: %i[security_secret_scanning_gitleaks security_secret_scanning_trufflehog].freeze,
        remedy: "No secret scanning found. Add gitleaks or trufflehog to CI."
      },
      static_analysis: {
        claim: "Source is scanned for known vulnerability patterns.",
        satisfied_by: %i[security_codeql_sast security_brakeman_sast].freeze,
        remedy: "No static analysis found. Add CodeQL or Brakeman to CI."
      },
      security_policy: {
        claim: "A security policy says how to report a vulnerability.",
        satisfied_by: %i[security_policy].freeze,
        remedy: "No security policy found. Add SECURITY.md."
      },
      ownership: {
        claim: "Ownership of protected paths is declared.",
        satisfied_by: %i[codeowners].freeze,
        remedy: "No ownership declaration found. Add CODEOWNERS."
      }
    }.freeze

    attr_reader :id, :claim, :satisfied_by, :remedy

    def initialize(id)
      @id = id.to_sym
      spec = REGISTRY.fetch(@id) do
        raise UnknownError, "Unknown security control #{id.inspect}. Known: #{REGISTRY.keys.join(", ")}."
      end
      @claim = spec[:claim]
      @satisfied_by = spec[:satisfied_by]
      @remedy = spec[:remedy]
      freeze
    end

    def self.fetch(id) = new(id)

    def self.ids = REGISTRY.keys

    def self.all = ids.map { |id| new(id) }

    # The criterion id this control is graded under. The control owns its own
    # naming so reports, waivers, and history cannot drift apart. Ids are
    # already namespaced under "security-", so a control named for security
    # drops the prefix rather than stuttering as security-security-policy.
    def criterion_id = :"security-#{id.to_s.delete_prefix("security_").tr("_", "-")}"

    # The first discovered fact that satisfies this control, or nil. Any one of
    # several fingerprints counts: the obligation is what matters, not the tool.
    #
    # @param discovery [DiscoveryResult]
    # @return [DiscoveredFact, nil]
    def evidence_in(discovery)
      satisfied_by.filter_map { |key| discovery[key] }.first
    end

    # Human-readable name for reports, e.g. "dependency review".
    def label = id.to_s.tr("_", " ")

    def to_sym = id

    def to_s = id.to_s
  end
end
