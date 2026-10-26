# frozen_string_literal: true

module Reanimator
  module Agents
    module Strategies
      # A narrow but genuine automated fixer: when an addition helper (a method
      # named add/sum/plus) subtracts its operands, rewrite the subtraction as
      # an addition. It is intentionally small - its job is to exercise the full
      # commissioning pipeline (plan, patch, isolated apply, independent
      # grading) with a real, deterministic repair rather than a stubbed answer.
      class ArithmeticFix < Base
        DEF = /def\s+(?:add|sum|plus)\b/
        SUBTRACTION = /\b([a-z_]\w*)\s*-\s*([a-z_]\w*)\b/

        def applies?(task) = !locate(task).nil?

        def call(task)
          path, _source, fixed = locate(task)
          plan = <<~PLAN.strip
            Objective: #{task.goal}
            1. Locate the addition helper that is subtracting its operands (#{path}).
            2. Replace the subtraction with an addition.
            3. Re-run the failing check to confirm the arithmetic is correct.
          PLAN
          [plan, Patch.write(path, fixed)]
        end

        private

        # Finds the first editable Ruby file whose addition helper subtracts,
        # returning [path, original, fixed] or nil.
        def locate(task)
          task.glob("**/*.rb").each do |relative|
            next unless task.may_edit?(relative)

            source = task.read(relative)
            next unless source&.match?(DEF)

            index = source.index(DEF)
            after = source[index..]
            next unless after.match?(SUBTRACTION)

            fixed = source[0...index] + after.sub(SUBTRACTION, '\1 + \2')
            return [relative, source, fixed]
          end
          nil
        end
      end
    end
  end
end
