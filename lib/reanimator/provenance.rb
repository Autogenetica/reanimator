# frozen_string_literal: true

module Reanimator
  # The audit trail behind a single discovered fact (specification section
  # 06): its source, how it was extracted, and when. Provenance is what lets
  # the interface always answer "Why does Reanimator believe this?" - no
  # fact exists in the system without one.
  class Provenance
    # @return [String] the concrete evidence, e.g. "reanimator.gemspec" or
    #   ".github/workflows/main.yml"
    attr_reader :source
    # @return [Symbol] extraction method, e.g. :file_present, :yaml_key,
    #   :regex_match, :git_metadata
    attr_reader :method
    # @return [String, nil] a short human-readable justification/excerpt
    attr_reader :detail
    # @return [Time] when the fact was extracted
    attr_reader :detected_at

    def initialize(source:, method:, detail: nil, detected_at: Time.now)
      @source = source
      @method = method.to_sym
      @detail = detail
      @detected_at = detected_at
      freeze
    end

    # A one-line, human-facing explanation of the evidence.
    # @return [String]
    def explanation
      base = "#{source} (#{method})"
      detail ? "#{base}: #{detail}" : base
    end

    def to_h
      {source: source, method: method, detail: detail, detected_at: detected_at.iso8601}
    end
  end
end
