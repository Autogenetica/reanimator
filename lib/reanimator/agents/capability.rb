# frozen_string_literal: true

module Reanimator
  module Agents
    # The capabilities an adapter can declare and a task can require
    # (specification section 08 commissioning step 1: "enumerate allowed
    # capabilities"). Tools are capability-scoped and deny-by-default (section
    # 12), so a task that needs a capability the profile does not offer is
    # routed elsewhere or refused - never silently attempted.
    module Capability
      # Produce a structured remediation plan.
      PLAN = :plan
      # Produce a patch (a set of file edits).
      PATCH = :patch
      # Edit repository files in a workspace.
      REPOSITORY_EDIT = :repository_edit
      # Execute checks in a sandbox.
      SANDBOX_EXEC = :sandbox_exec
      # Reach the network (subject to egress policy).
      NETWORK = :network

      ALL = [PLAN, PATCH, REPOSITORY_EDIT, SANDBOX_EXEC, NETWORK].freeze

      module_function

      def valid?(capability) = ALL.include?(capability.to_sym)
    end
  end
end
