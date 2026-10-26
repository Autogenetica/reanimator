# frozen_string_literal: true

module Reanimator
  module Detectors
    # Detects that a repository is a fork and, when possible, its upstream
    # (specification section 04 cohorts and section 10 relationships). A fork
    # is classified differently from an active original - it may be upstream
    # observation, divergence monitoring, or a candidate to retire - so knowing
    # the fork relationship early shapes the entire onboarding default.
    class Fork < Base
      def detect
        upstream = Git.capture(repository.path, "config", "--get", "remote.upstream.url")
        return [] unless repository.fork? || upstream

        upstream_name = RepositoryMetadata.full_name_from_url(upstream)
        claim = upstream_name ? "A fork of #{upstream_name}." : "A fork with a configured upstream remote."

        [fact(:fork_of, category: :relationships,
          claim: claim, value: upstream_name, confidence: :high,
          source: upstream ? "remote.upstream" : "git metadata", method: :git_metadata,
          detail: upstream_name)]
      end
    end
  end
end
