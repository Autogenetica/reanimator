# frozen_string_literal: true

require "yaml"
require "date"

module Reanimator
  # Reads and writes the optional, repository-owned .reanimator.yml
  # (specification section 07). The target for ordinary configuration is tiny -
  # "one lifecycle decision and one reusable profile" - but the same file can
  # carry the full resolved schema for advanced owners. Export must round-trip
  # without semantic loss, so this class is the single reader and writer for
  # that format.
  class ContractFile
    CURRENT_VERSION = 1

    # @return [Hash] the parsed document with symbol keys
    attr_reader :data
    # @return [String, nil] path the document was loaded from
    attr_reader :source_path

    def initialize(data, source_path: nil)
      @data = normalize(data)
      @source_path = source_path
      validate!
    end

    # Loads the contract file from a repository root, or returns nil when the
    # owner has not committed one (the common, YAML-free case).
    #
    # @param root [String]
    # @param filename [String]
    # @return [ContractFile, nil]
    def self.load(root, filename = Reanimator.configuration.contract_filename)
      full = File.join(root, filename)
      return nil unless File.file?(full)

      # Date/Time are permitted so a waiver's `expires:` can be a bare date
      # literal; no other non-primitive classes are allowed to load.
      raw = YAML.safe_load_file(full, permitted_classes: [Date, Time], aliases: false) || {}
      new(raw, source_path: full)
    rescue Psych::SyntaxError => e
      raise ContractError, "#{filename} is not valid YAML: #{e.message}"
    end

    # Serializes a contract hash (typically {EffectiveContract#to_contract_hash})
    # back to YAML. Keys are stringified and ordered for a stable, diff-friendly
    # export.
    #
    # @param hash [Hash]
    # @return [String]
    def self.dump(hash)
      YAML.dump(stringify(hash)).sub(/\A---\n/, "")
    end

    def version = data.fetch(:version, CURRENT_VERSION)

    # @return [Symbol, nil]
    def intent
      value = data[:intent]
      value&.to_sym
    end

    # @return [Symbol, nil]
    def profile
      value = data[:profile]
      value&.to_sym
    end

    def agents = data[:agents] || {}

    def acceptance = data[:acceptance] || {}

    def security = data[:security] || {}

    def autonomy = data[:autonomy] || {}

    def upgrades = data[:upgrades] || {}

    def notifications = data[:notifications] || {}

    def waivers = data[:waivers] || []

    def family = data[:family]

    def to_yaml = ContractFile.dump(data)

    private

    def validate!
      unless version.is_a?(Integer)
        raise ContractError, "Contract version must be an integer, got #{version.inspect}."
      end
      if intent && !LifecycleIntent.valid?(intent)
        raise ContractError, "Unknown lifecycle intent #{intent.inspect} in contract."
      end
    end

    def normalize(value)
      case value
      when Hash then value.each_with_object({}) { |(k, v), h| h[k.to_sym] = normalize(v) }
      when Array then value.map { |v| normalize(v) }
      else value
      end
    end

    def self.stringify(value)
      case value
      when Hash then value.each_with_object({}) { |(k, v), h| h[k.to_s] = stringify(v) }
      when Array then value.map { |v| stringify(v) }
      when Symbol then value.to_s
      else value
      end
    end
    private_class_method :stringify
  end
end
