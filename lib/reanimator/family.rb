# frozen_string_literal: true

module Reanimator
  # A graph of repositories whose health must be evaluated together
  # (specification sections 02 and 10) - a gem and its executable examples, an
  # application and its client, a project and its deployment samples. A family
  # is the unit that answers "keep connected projects alive together": it knows
  # its members and their roles, the typed edges between them, and the gates
  # that make one member's proof a condition of another's.
  class Family
    # One repository inside a family. `path` is where it lives locally, when
    # known - a gate can only run a downstream check if it can reach it.
    Member = Struct.new(:full_name, :role, :path) do
      def to_h = {full_name: full_name, role: role, path: path}.compact
    end

    attr_reader :id, :members, :gates, :relationships

    def initialize(id:, members: [], gates: [], relationships: [])
      @id = id.to_sym
      @members = members
      @gates = gates
      @relationships = relationships
    end

    # @return [Member, nil]
    def member(full_name)
      members.find { |m| m.full_name == full_name }
    end

    def member?(full_name) = !member(full_name).nil?

    def size = members.size

    # Members holding a given role, e.g. :compatibility_suite.
    def with_role(role)
      members.select { |m| m.role == role.to_sym }
    end

    # The edge between two members, used to name exactly what broke.
    def relationship_between(upstream, downstream)
      relationships.find { |r| r.to == upstream && r.from == downstream }
    end

    # Parses the section 10 family-policy shape:
    #
    #   family:
    #     id: agentic
    #     members:
    #       codenamev/agentic: {role: library}
    #       codenamev/agentic-examples: {role: compatibility-suite}
    #     gates:
    #       - on: codenamev/agentic
    #         require: {repository: codenamev/agentic-examples, check: bin/smoke}
    #
    # @param declaration [Hash]
    # @param paths [Hash{String=>String}] optional full_name => local path
    # @return [Family]
    def self.from_declaration(declaration, paths: {})
      raise ContractError, "A family declaration needs an id." unless declaration[:id]

      members = (declaration[:members] || {}).map do |full_name, attributes|
        name = full_name.to_s
        role = (attributes || {})[:role] || :member
        Member.new(name, role.to_s.tr("-", "_").to_sym, paths[name])
      end

      gates = (declaration[:gates] || []).map do |gate|
        required = gate[:require] || {}
        Gate.new(
          on: gate[:on].to_s,
          requires_repository: required[:repository].to_s,
          check: required[:check]
        )
      end

      new(id: declaration[:id], members: members, gates: gates)
    end

    def to_h
      {
        id: id,
        members: members.map(&:to_h),
        relationships: relationships.map(&:to_h),
        gates: gates.map(&:to_h)
      }
    end
  end
end
