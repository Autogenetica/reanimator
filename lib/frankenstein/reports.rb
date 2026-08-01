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
  end
end
