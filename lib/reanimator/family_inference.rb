# frozen_string_literal: true

module Reanimator
  # Infers repository families from a portfolio (specification section 10).
  # The strongest signals are structural and cheap: a repository named
  # `<project>-examples` is that project's compatibility suite,
  # `<project>-example-heroku` is a deployment example, `<project>-docs` is its
  # documentation, and `<host>-<project>` is a plugin for a project that is
  # itself in the portfolio.
  #
  # Inference is deliberately conservative - it only proposes an edge it can
  # point at concrete evidence for. An owner-declared family always wins, and
  # weaker "these names look related" hunches are left to declaration rather
  # than turned into obligations.
  module FamilyInference
    # Each rule maps a repository name to the project it depends on, and the
    # kind of dependence that implies.
    SUFFIX_RULES = [
      [/\A(?<base>.+?)[-_]examples?\z/, :compatibility_suite],
      [/\A(?<base>.+?)[-_]example[-_].+\z/, :deployment_example],
      [/\A(?<base>.+?)[-_]docs?\z/, :documentation_for]
    ].freeze

    module_function

    # @param portfolio [Portfolio]
    # @return [Array<Family>] families with at least one edge, id-sorted
    def call(portfolio)
      repositories = portfolio.entries.map(&:repository)
      declared = declared_families(repositories)
      inferred = inferred_families(repositories, declared)

      (declared.values + inferred.values).sort_by { |family| family.id.to_s }
    end

    # Families a repository explicitly joined via `family: {id:, role:}`.
    def declared_families(repositories)
      repositories.each_with_object({}) do |repository, families|
        declaration = repository.declared&.family
        next unless declaration.is_a?(Hash) && declaration[:id]

        id = declaration[:id].to_sym
        role = (declaration[:role] || :member).to_s.tr("-", "_").to_sym
        family = families[id] ||= Family.new(id: id)
        family.members << Family::Member.new(repository.full_name, role, repository.path)
      end
    end

    # Families implied by naming structure, skipping any repository that has
    # already declared its membership.
    def inferred_families(repositories, declared)
      claimed = declared.values.flat_map { |f| f.members.map(&:full_name) }
      by_name = repositories.each_with_object({}) { |r, index| index[r.name] = r }
      by_full_name = repositories.each_with_object({}) { |r, index| index[r.full_name] = r }

      edges = repositories.filter_map do |repository|
        next if claimed.include?(repository.full_name)

        relationship = relate(repository, by_name)
        # Declaration wins over inference on *both* ends: once an owner has
        # placed a repository in a family, we do not invent a competing family
        # around it, even as the upstream of someone else's edge.
        next if relationship.nil? || claimed.include?(relationship.to)

        relationship
      end

      build_families(edges, by_full_name)
    end

    # The edge this repository implies, or nil when nothing matches.
    def relate(repository, by_name)
      SUFFIX_RULES.each do |pattern, type|
        match = repository.name.match(pattern)
        next unless match && by_name.key?(match[:base])

        return edge(repository, by_name[match[:base]], type, "name #{repository.name} implies #{match[:base]}")
      end

      plugin_edge(repository, by_name)
    end

    # `ruby_llm-ups` is a plugin for `ups` when `ups` is itself in the portfolio.
    def plugin_edge(repository, by_name)
      host = repository.name.split(/[-_]/).last
      return if host.nil? || host == repository.name
      return unless by_name.key?(host)

      edge(repository, by_name[host], :plugin_for, "name #{repository.name} targets #{host}")
    end

    def edge(dependent, upstream, type, evidence)
      return if dependent.full_name == upstream.full_name

      Relationship.new(from: dependent.full_name, to: upstream.full_name, type: type, evidence: evidence)
    end

    # Groups edges by their upstream project into one family each, with a gate
    # per edge so every dependence has something that proves it.
    def build_families(edges, by_full_name)
      edges.group_by(&:to).each_with_object({}) do |(upstream_name, group), families|
        upstream = by_full_name.fetch(upstream_name)

        members = [Family::Member.new(upstream_name, :library, upstream.path)] +
          group.map { |edge| Family::Member.new(edge.from, edge.role, by_full_name[edge.from]&.path) }
        gates = group.map { |edge| Family::Gate.new(on: upstream_name, requires_repository: edge.from) }

        families[upstream.name.to_sym] =
          Family.new(id: upstream.name, members: members, gates: gates, relationships: group)
      end
    end
  end
end
