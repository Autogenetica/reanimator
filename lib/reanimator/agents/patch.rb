# frozen_string_literal: true

require "fileutils"

module Reanimator
  module Agents
    # A proposed change expressed as data, not as a mutation the agent performs
    # itself. Representing a repair as a set of file edits is what lets the
    # harness - never the agent - apply it into an isolated evaluation
    # workspace (specification section 09: evaluation runs separately from the
    # agent workspace). An agent proposes a Patch; Reanimator decides whether
    # and where to apply it.
    class Patch
      # A single file's new contents (or deletion).
      Edit = Struct.new(:path, :contents, :delete) do
        def delete? = delete
      end

      attr_reader :edits

      def initialize(edits = [])
        @edits = edits
      end

      def self.write(path, contents)
        new([Edit.new(path: path, contents: contents, delete: false)])
      end

      def empty? = edits.empty?

      def paths = edits.map(&:path)

      # Applies the patch beneath a root directory. The harness calls this on a
      # disposable copy; agents never call it. Refuses to escape the root.
      #
      # @param root [String]
      # @raise [PolicyViolation] when an edit path escapes the root
      def apply(root)
        edits.each do |edit|
          full = File.expand_path(File.join(root, edit.path))
          unless full.start_with?(File.expand_path(root) + File::SEPARATOR)
            raise PolicyViolation, "Patch edit #{edit.path.inspect} escapes the workspace root."
          end

          if edit.delete?
            File.delete(full) if File.exist?(full)
          else
            FileUtils.mkdir_p(File.dirname(full))
            File.write(full, edit.contents)
          end
        end
        root
      end

      def to_h
        {edits: edits.map { |e| {path: e.path, delete: e.delete?} }}
      end
    end
  end
end
