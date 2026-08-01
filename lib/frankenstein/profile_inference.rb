# frozen_string_literal: true

module Frankenstein
  # Chooses the vitality profile a repository most likely wants, from its
  # discovered facts (specification section 06). The choice is a suggestion,
  # not a decision - it is preselected and shown with its reasoning, and an
  # owner-declared profile always wins over it (handled in the resolver).
  module ProfileInference
    module_function

    # @param discovery [DiscoveryResult]
    # @return [DiscoveryResult::Suggestion]
    def call(discovery)
      if discovery.fact?(:rails_app)
        suggest(:"rails-app", :high, "config/application.rb boots Rails.")
      elsif discovery.fact?(:fork_of)
        suggest(:"maintained-fork", :high, "The repository is a fork with an upstream.")
      elsif discovery.fact?(:ruby_gem)
        if discovery.fact?(:executables)
          suggest(:"ruby-cli", :high, "A gemspec plus shipped executables indicate a CLI.")
        else
          suggest(:"ruby-gem", :high, "A gemspec indicates a published gem.")
        end
      elsif discovery.fact?(:bundler)
        suggest(:generic, :medium, "A Ruby project without a gemspec or Rails app; using the generic profile.")
      else
        suggest(:generic, :low, "No strong ecosystem signal; using the generic profile.")
      end
    end

    def suggest(profile, confidence, reason)
      DiscoveryResult::Suggestion.new(
        profile: profile, confidence: Confidence[confidence], reason: reason
      )
    end
  end
end
