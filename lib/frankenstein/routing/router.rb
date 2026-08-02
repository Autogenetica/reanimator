# frozen_string_literal: true

module Frankenstein
  module Routing
    # Chooses which ready profile performs a task (specification section 08
    # routing strategies). Provider choice is an execution concern, not the
    # repository's definition of life, so routing operates entirely on
    # commissioned profiles and always produces a visible explanation. Fallback
    # is considered only when explicitly declared, and only across profiles that
    # share a data-handling policy.
    class Router
      STRATEGIES = %i[auto pinned ordered task_routed local_only manual].freeze

      def initialize(profiles, strategy: :auto, order: [], pin: nil, fallback: [], task_routes: {})
        @profiles = profiles
        @strategy = strategy.to_sym
        @order = Array(order).map(&:to_sym)
        @pin = pin&.to_sym
        @fallback = Array(fallback)
        @task_routes = task_routes
        raise UnknownError, "Unknown routing strategy #{strategy.inspect}." unless STRATEGIES.include?(@strategy)
      end

      # @param required_capabilities [Array<Symbol>]
      # @param task_class [Symbol, nil]
      # @return [Decision]
      def select(required_capabilities: [], task_class: nil)
        excluded = []
        eligible = @profiles.select do |profile|
          reason = ineligibility(profile, required_capabilities, task_class)
          excluded << {provider: profile.provider, reason: reason} if reason
          reason.nil?
        end

        chosen = choose(eligible, task_class)
        fallbacks = chosen ? declared_fallbacks(chosen) : []

        Decision.new(
          profile: chosen, strategy: @strategy, excluded: excluded, fallbacks: fallbacks,
          explanation: explain(chosen, excluded, fallbacks, required_capabilities, task_class)
        )
      end

      private

      # Returns a reason string when a profile cannot be used, else nil.
      def ineligibility(profile, required_capabilities, task_class)
        return "it is not commissioned ready (#{profile.readiness})" unless profile.ready?

        missing = required_capabilities.map(&:to_sym) - profile.capabilities
        return "it lacks required capabilities: #{missing.join(", ")}" if missing.any?

        case @strategy
        when :local_only
          "it is not a local profile" unless profile.connection.local?
        when :pinned
          "it is not the pinned provider (#{@pin})" unless profile.provider == @pin
        when :task_routed
          expected = @task_routes[task_class]
          "task #{task_class} routes to #{expected}, not #{profile.provider}" if expected && profile.provider != expected
        end
      end

      def choose(eligible, task_class)
        return nil if @strategy == :manual

        case @strategy
        when :ordered
          @order.filter_map { |provider| eligible.find { |p| p.provider == provider } }.first
        when :pinned
          eligible.find { |p| p.provider == @pin }
        when :task_routed
          eligible.find { |p| p.provider == @task_routes[task_class] } || prefer(eligible)
        else # auto, local_only
          prefer(eligible)
        end
      end

      # Prefer local (cheapest, most private), then declared order, else stable.
      def prefer(eligible)
        eligible.min_by.with_index do |profile, index|
          [profile.connection.local? ? 0 : 1, order_rank(profile), index]
        end
      end

      def order_rank(profile)
        rank = @order.index(profile.provider)
        rank || @order.size
      end

      # Fallback is never implied: only explicitly declared profiles that are
      # ready and share the chosen profile's data-handling policy qualify.
      def declared_fallbacks(chosen)
        @fallback.select { |f| f.ready? && f != chosen && f.same_data_handling?(chosen) }
      end

      def explain(chosen, excluded, fallbacks, required_capabilities, task_class)
        parts = []
        if chosen
          because = ["it is commissioned ready"]
          because << "offers #{required_capabilities.join(", ")}" if required_capabilities.any?
          parts << "Selected #{chosen.provider} (#{@strategy}) because #{because.join(" and ")}."
          parts << "Task class: #{task_class}." if task_class
          parts << if fallbacks.any?
            "#{fallbacks.map(&:provider).join(", ")} configured as fallback (same data-handling policy)."
          else
            "No fallback is configured; fallback is never implied."
          end
        else
          parts << if @strategy == :manual
            "No agent was auto-selected: manual routing defers the choice to you."
          else
            "No eligible agent profile was found."
          end
          parts << "Observation and baseline remain automatic."
        end
        excluded.each { |e| parts << "#{e[:provider]} was excluded because #{e[:reason]}." }
        parts.join(" ")
      end
    end
  end
end
