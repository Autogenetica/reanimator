# frozen_string_literal: true

module Frankenstein
  # Plain-text reporters. They build deterministic strings with no color or
  # TTY dependency so they are trivially testable; the CLI layers on boxes and
  # color when a human is watching. The output style mirrors the specification's
  # own artifacts (the section 15 GitHub check and the Appendix A baseline).
  module Reports
    # Status glyphs shared across reporters.
    GLYPH = {
      verified: "✓",
      failed: "✗",
      missing_evidence: "•",
      skipped: "◦",
      accepted_risk: "!",
      planned: "…",
      error: "✗"
    }.freeze

    module_function

    def glyph(status) = GLYPH.fetch(status.to_sym, "·")

    # Human-readable label for a result status.
    def status_label(status)
      status.to_s.tr("_", " ")
    end

    # "1 repository" / "3 repositories". Every reporter needs to put a number
    # in front of a noun, and each had grown its own spelling of it - which is
    # how a user eventually reads "1 repositorys".
    def count(size, singular, plural = "#{singular}s")
      "#{size} #{(size == 1) ? singular : plural}"
    end
  end
end
