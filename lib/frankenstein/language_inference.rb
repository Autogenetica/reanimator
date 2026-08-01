# frozen_string_literal: true

module Frankenstein
  # A cheap primary-language guess from file extensions. This is intentionally
  # crude - it exists to seed cohort heuristics and reports, not to replace a
  # linguist. When git is present it counts tracked files (fast and respectful
  # of .gitignore); otherwise it falls back to a bounded directory walk.
  module LanguageInference
    EXTENSIONS = {
      ".rb" => "Ruby", ".rake" => "Ruby", ".gemspec" => "Ruby",
      ".js" => "JavaScript", ".mjs" => "JavaScript", ".ts" => "TypeScript",
      ".py" => "Python", ".go" => "Go", ".rs" => "Rust",
      ".java" => "Java", ".kt" => "Kotlin", ".c" => "C", ".h" => "C",
      ".cpp" => "C++", ".cs" => "C#", ".php" => "PHP",
      ".ex" => "Elixir", ".exs" => "Elixir", ".erl" => "Erlang",
      ".swift" => "Swift", ".sh" => "Shell", ".crystal" => "Crystal", ".cr" => "Crystal"
    }.freeze

    MAX_WALK_FILES = 5_000

    module_function

    # @param root [String]
    # @return [String, nil] the most common recognized language, or nil
    def call(root)
      counts = Hash.new(0)
      files(root).each do |rel|
        language = EXTENSIONS[File.extname(rel)]
        counts[language] += 1 if language
      end
      counts.max_by { |_lang, n| n }&.first
    end

    def files(root)
      tracked = Git.tracked_files(root)
      return tracked unless tracked.empty?

      Dir.glob("**/*", base: root, flags: File::FNM_DOTMATCH)
        .reject { |rel| rel.start_with?(".git/") }
        .first(MAX_WALK_FILES)
    end
  end
end
