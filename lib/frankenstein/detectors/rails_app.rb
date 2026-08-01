# frozen_string_literal: true

module Frankenstein
  module Detectors
    # Detects a Ruby on Rails application (specification section 06: Ecosystem
    # and Deployment). The signal is a config/application.rb that boots Rails,
    # optionally corroborated by a `rails` dependency and a bin/rails script.
    # Deployment surfaces (Kamal, Docker, Compose) are recorded so the resolver
    # can flag protected paths.
    class RailsApp < Base
      def detect
        return [] unless rails?

        facts = [
          fact(:rails_app, category: :ecosystem,
            claim: "A Ruby on Rails application.",
            confidence: :high, source: "config/application.rb", method: :file_present)
        ]

        deployment_facts.each { |f| facts << f }
        facts
      end

      private

      def rails?
        return false unless repository.exist?("config/application.rb")

        body = repository.read("config/application.rb").to_s
        body.include?("Rails::Application") || repository.exist?("bin/rails")
      end

      DEPLOYMENT_EVIDENCE = {
        "config/deploy.yml" => "Kamal deployment",
        "Dockerfile" => "Docker image build",
        "docker-compose.yml" => "Docker Compose services",
        "compose.yaml" => "Docker Compose services"
      }.freeze

      def deployment_facts
        DEPLOYMENT_EVIDENCE.filter_map do |path, description|
          next unless repository.exist?(path)

          fact(:"deploy_#{File.basename(path, ".*").downcase}", category: :deployment,
            claim: "Deployment surface: #{description}.",
            confidence: :high, source: path, method: :file_present)
        end
      end
    end
  end
end
