# frozen_string_literal: true

require "json"

module Reanimator
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
    # `taken_at` is normalized to an ISO-8601 string on the way in: a snapshot
    # exists to be written down and read back, so the moment it records reads
    # the same whether it was just taken or loaded from a file.
    attr_reader :repository, :origin, :intent, :profile, :security_posture, :autonomy,
      :protected_paths, :criteria, :waivers, :support_matrix, :security_controls, :taken_at

    def initialize(repository:, intent:, profile:, security_posture:, autonomy: {},
      protected_paths: [], criteria: [], waivers: [], support_matrix: [],
      security_controls: [], origin: nil, taken_at: nil)
      @repository = immutable(repository)
      @origin = immutable(origin)
      @intent = intent
      @profile = profile
      @security_posture = security_posture
      @autonomy = immutable(autonomy)
      @protected_paths = immutable(protected_paths)
      @criteria = immutable(criteria)
      @waivers = immutable(waivers)
      @support_matrix = immutable(support_matrix)
      @security_controls = immutable(security_controls)
      @taken_at = taken_at.is_a?(Time) ? taken_at.iso8601 : taken_at
      freeze
    end

    # A snapshot records what was true at a moment, so it must not be editable
    # afterwards - and `freeze` alone does not achieve that, because it leaves
    # the recorded arrays and hashes writable. Copies are frozen rather than
    # the caller's own collections, so recording a contract never freezes the
    # live contract.
    def immutable(value)
      case value
      when Hash then value.transform_values { |entry| immutable(entry) }.freeze
      when Array then value.map { |entry| immutable(entry) }.freeze
      when String then value.frozen? ? value : value.dup.freeze
      else value
      end
    end
    private :immutable

    # @param contract [EffectiveContract]
    # @return [ContractSnapshot]
    def self.of(contract, taken_at: Time.now)
      discovery = contract.discovery

      new(
        repository: contract.repository.full_name,
        origin: Git.origin_url(contract.repository.path),
        intent: contract.intent.to_sym,
        profile: contract.profile.id,
        security_posture: contract.security_posture.to_sym,
        autonomy: contract.autonomy,
        protected_paths: contract.protected_paths,
        criteria: contract.criteria.map { |criterion| record_criterion(criterion) },
        waivers: contract.waivers.map { |waiver| record_waiver(waiver) },
        support_matrix: discovered_matrix(discovery),
        security_controls: discovered_controls(discovery),
        taken_at: taken_at
      )
    end

    def self.record_criterion(criterion)
      {id: criterion.id, evaluator: criterion.evaluator, run: criterion.run, required: criterion.required?}
    end
    private_class_method :record_criterion

    def self.record_waiver(waiver)
      {target: waiver.target, expires: waiver.expires&.iso8601}
    end
    private_class_method :record_waiver

    # What CI actually exercises, falling back to what the project declares.
    def self.discovered_matrix(discovery)
      return [] unless discovery

      Array(discovery.value(:ci_ruby_matrix) || discovery.value(:supported_ruby)).map(&:to_s)
    end
    private_class_method :discovered_matrix

    def self.discovered_controls(discovery)
      return [] unless discovery

      discovery.in_category(:security_controls).map(&:key).sort
    end
    private_class_method :discovered_controls

    # Rebuilds a snapshot from its serialized form, tolerating the string keys
    # a JSON round-trip produces.
    def self.from_h(hash)
      data = symbolize(hash)
      unless data.is_a?(Hash) && data.key?(:repository)
        raise ContractError,
          "That is not a contract snapshot; expected the JSON object written by `reanimator drift --save`."
      end

      new(
        repository: data[:repository],
        origin: data[:origin],
        intent: data[:intent]&.to_sym,
        profile: data[:profile]&.to_sym,
        security_posture: data[:security_posture]&.to_sym,
        autonomy: (data[:autonomy] || {}).transform_values(&:to_sym),
        protected_paths: Array(data[:protected_paths]).map(&:to_s),
        criteria: Array(data[:criteria]).map { |criterion| restore_criterion(criterion) },
        waivers: Array(data[:waivers]).map { |waiver| restore_waiver(waiver) },
        support_matrix: Array(data[:support_matrix]).map(&:to_s),
        security_controls: Array(data[:security_controls]).map(&:to_sym),
        taken_at: data[:taken_at]
      )
    end

    def self.restore_criterion(criterion)
      {
        id: criterion[:id]&.to_sym, evaluator: criterion[:evaluator]&.to_sym,
        run: criterion[:run], required: criterion[:required]
      }
    end
    private_class_method :restore_criterion

    def self.restore_waiver(waiver)
      {target: waiver[:target]&.to_sym, expires: waiver[:expires]}
    end
    private_class_method :restore_waiver

    def self.load(path)
      from_h(JSON.parse(File.read(path, encoding: "UTF-8")))
    rescue JSON::ParserError => e
      raise ContractError, "#{path} is not a valid contract snapshot: #{e.message}"
    rescue Errno::ENOENT
      raise ContractError, "No contract snapshot at #{path}."
    rescue SystemCallError => e
      raise ContractError, "Could not read the contract snapshot at #{path}: #{e.message}"
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

    # Whether a recorded criterion was blocking. Asked rather than dug out of
    # the criterion hash, so callers never have to know its shape.
    def requires?(id) = criterion(id)&.fetch(:required, false) == true

    def waiver_targets = waivers.map { |w| w[:target] }

    # When accepted risk for a target runs out, or nil for open-ended.
    def waiver_expiry(target)
      waivers.find { |waiver| waiver[:target] == target }&.[](:expires)
    end

    def to_h
      {
        repository: repository, origin: origin,
        taken_at: taken_at,
        intent: intent, profile: profile, security_posture: security_posture,
        autonomy: autonomy, protected_paths: protected_paths, criteria: criteria,
        waivers: waivers, support_matrix: support_matrix, security_controls: security_controls
      }
    end

    def to_json(*args) = JSON.pretty_generate(to_h, *args)
  end
end
