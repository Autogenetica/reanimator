# frozen_string_literal: true

require "date"
require "time"

module Frankenstein
  # An explicit, scoped, attributable exception to an obligation (specification
  # section 09). A waiver does not make a failing criterion pass - "a waived
  # obligation is not counted as verified; it is counted as accepted risk". It
  # is time-bounded when appropriate: past its expiry it stops applying and the
  # obligation is blocking again (fail closed). A waiver always carries a
  # rationale, so accepted risk is never anonymous.
  class Waiver
    # @return [Symbol] the acceptance-criterion id this waiver accepts
    attr_reader :target
    # @return [String] why the risk is accepted (required)
    attr_reader :reason
    # @return [String] who accepted it
    attr_reader :owner
    # @return [Hash] optional scope (environments, paths, family members)
    attr_reader :scope
    # @return [Time, nil] when the waiver stops applying, or nil for open-ended
    attr_reader :expires

    def initialize(target:, reason:, owner: "repository", scope: {}, expires: nil)
      @target = target.to_sym
      @reason = reason.to_s
      @owner = owner
      @scope = scope || {}
      @expires = coerce_time(expires)
      if @reason.strip.empty?
        raise ContractError, "Waiver for #{target.inspect} needs a reason; accepted risk must be attributable."
      end
    end

    # @param criterion_id [Symbol, String]
    def covers?(criterion_id) = target == criterion_id.to_sym

    # Whether the waiver still applies at the given time.
    def active?(now: Time.now) = expires.nil? || now < expires

    def expired?(now: Time.now) = !active?(now: now)

    def to_h
      {target: target, reason: reason, owner: owner, expires: expires&.iso8601}.compact
    end

    private

    # Accepts a Date or Time (from YAML) or a parseable string; nil means
    # open-ended.
    def coerce_time(value)
      case value
      when nil then nil
      when Time then value
      when Date then value.to_time
      else Time.parse(value.to_s)
      end
    rescue ArgumentError
      raise ContractError, "Waiver for #{target.inspect} has an invalid expires: #{value.inspect}."
    end
  end
end
