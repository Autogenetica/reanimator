# frozen_string_literal: true

require "json"

module Frankenstein
  # A comparable, serializable picture of what a repository was required to
  # prove at a point in time. Configuration drift (specification section 06) is
  # a comparison between two of these: the contract as it was last recorded,
  # and the contract the current evidence resolves to.
  #
  # It deliberately captures more than the contract alone. "A removed security
  # gate" and "a narrowed runtime matrix" are the section 06 examples of a
  # policy change, and both live in discovered evidence rather than in the
  # declared file, so the snapshot carries them too.
  class ContractSnapshot
    attr_reader :repository, :intent, :profile, :security_posture, :autonomy,
      :protected_paths, :criteria, :waivers, :support_matrix, :security_controls, :taken_at

    def initialize(repository:, intent:, profile:, security_posture:, autonomy: {},
      protected_paths: [], criteria: [], waivers: [], support_matrix: [],
      security_controls: [], taken_at: nil)
      @repository = repository
      @intent = intent
      @profile = profile
      @security_posture = security_posture
      @autonomy = autonomy
      @protected_paths = protected_paths
      @criteria = criteria
      @waivers = waivers
      @support_matrix = support_matrix
      @security_controls = security_controls
      @taken_at = taken_at
      freeze
    end

    # @param contract [EffectiveContract]
    # @return [ContractSnapshot]
    def self.of(contract, taken_at: Time.now)
      discovery = contract.discovery

      new(
        repository: contract.repository.full_name,
        intent: contract.intent.to_sym,
        profile: contract.profile.id,
        security_posture: contract.security_posture.to_sym,
        autonomy: contract.autonomy,
        protected_paths: contract.protected_paths,
        criteria: contract.criteria.map do |criterion|
          {id: criterion.id, evaluator: criterion.evaluator, run: criterion.run, required: criterion.required?}
        end,
        waivers: contract.waivers.map { |waiver| {target: waiver.target, expires: waiver.expires&.iso8601} },
        support_matrix: runtime_matrix(discovery),
        security_controls: discovery ? discovery.in_category(:security_controls).map(&:key).sort : [],
        taken_at: taken_at
      )
    end

    # What CI actually exercises, falling back to what the project declares.
    def self.runtime_matrix(discovery)
      return [] unless discovery

      Array(discovery.value(:ci_ruby_matrix) || discovery.value(:supported_ruby)).map(&:to_s)
    end

    # Rebuilds a snapshot from its serialized form, tolerating the string keys
    # a JSON round-trip produces.
    def self.from_h(hash)
      data = symbolize(hash)

      new(
        repository: data[:repository],
        intent: data[:intent]&.to_sym,
        profile: data[:profile]&.to_sym,
        security_posture: data[:security_posture]&.to_sym,
        autonomy: (data[:autonomy] || {}).transform_values(&:to_sym),
        protected_paths: Array(data[:protected_paths]).map(&:to_s),
        criteria: Array(data[:criteria]).map do |criterion|
          {
            id: criterion[:id]&.to_sym, evaluator: criterion[:evaluator]&.to_sym,
            run: criterion[:run], required: criterion[:required]
          }
        end,
        waivers: Array(data[:waivers]).map { |waiver| {target: waiver[:target]&.to_sym, expires: waiver[:expires]} },
        support_matrix: Array(data[:support_matrix]).map(&:to_s),
        security_controls: Array(data[:security_controls]).map(&:to_sym),
        taken_at: data[:taken_at]
      )
    end

    def self.load(path)
      from_h(JSON.parse(File.read(path, encoding: "UTF-8")))
    rescue JSON::ParserError => e
      raise ContractError, "#{path} is not a valid contract snapshot: #{e.message}"
    rescue Errno::ENOENT
      raise ContractError, "No contract snapshot at #{path}."
    end

    def self.symbolize(value)
      case value
      when Hash then value.each_with_object({}) { |(k, v), h| h[k.to_sym] = symbolize(v) }
      when Array then value.map { |v| symbolize(v) }
      else value
      end
    end
    private_class_method :symbolize

    # The criterion recorded under an id, or nil.
    def criterion(id)
      criteria.find { |c| c[:id] == id }
    end

    def criterion_ids = criteria.map { |c| c[:id] }

    def waiver_targets = waivers.map { |w| w[:target] }

    def to_h
      {
        repository: repository, taken_at: taken_at.is_a?(Time) ? taken_at.iso8601 : taken_at,
        intent: intent, profile: profile, security_posture: security_posture,
        autonomy: autonomy, protected_paths: protected_paths, criteria: criteria,
        waivers: waivers, support_matrix: support_matrix, security_controls: security_controls
      }
    end

    def to_json(*args) = JSON.pretty_generate(to_h, *args)
  end
end
