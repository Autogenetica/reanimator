# frozen_string_literal: true

module Reanimator
  module Detectors
    # Detects cross-repository edges (specification section 06: Relationships,
    # and section 10: repository families). Path dependencies, submodules, and
    # documentation links are the seams where "keep connected projects alive
    # together" begins - each edge is a candidate member of a repository
    # family whose health must be evaluated jointly.
    class Relationships < Base
      GEM_PATH = /gem\s+['"]([^'"]+)['"].*\bpath:\s*['"]([^'"]+)['"]/
      GITHUB_REF = %r{github\.com[:/]([\w.-]+/[\w.-]+?)(?:\.git|/|["')\s]|\z)}

      def detect
        facts = path_dependency_facts
        facts.concat(submodule_facts)
        facts
      end

      private

      def path_dependency_facts
        gemfile = repository.read("Gemfile")
        return [] unless gemfile

        gemfile.scan(GEM_PATH).map do |gem_name, local_path|
          fact(:"path_dep_#{gem_name.gsub(/[^a-z0-9]+/i, "_")}", category: :relationships,
            claim: "Depends on a local path gem: #{gem_name} (#{local_path}).",
            value: {gem: gem_name, path: local_path}, confidence: :high,
            source: "Gemfile", method: :manifest_parse, detail: local_path)
        end
      end

      def submodule_facts
        body = repository.read(".gitmodules")
        return [] unless body

        body.scan(GITHUB_REF).flatten.uniq.map do |full_name|
          fact(:"submodule_#{full_name.gsub(%r{[^a-z0-9]+}i, "_")}", category: :relationships,
            claim: "Includes submodule #{full_name}.",
            value: full_name, confidence: :high, source: ".gitmodules", method: :manifest_parse, detail: full_name)
        end
      end
    end
  end
end
