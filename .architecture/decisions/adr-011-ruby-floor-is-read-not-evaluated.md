# ADR-011: A gem's Ruby floor is read, never evaluated

- Status: Accepted
- Date: 2026-11-02

## Context

`support_matrix` compares the Ruby floor a gem declares with the Rubies its CI
exercises. The floor lives in `required_ruby_version`, inside a gemspec, which
is Ruby code. `Gem::Specification.load` would give the exact answer, and it is
the one thing Reanimator cannot do: loading a gemspec runs repository code in
the invoking user's process, with that user's files, credentials and network.
A read-only first run (ADR-001) and the safety floor (ADR-003) rule that out,
and executed checks have no user or filesystem isolation yet (§12).

So the floor is read as text, and a text reader can be wrong. Eleven
adversarial reviews of the reader found the same shape again and again: some
way of writing a floor that the reader missed, read as "no floor", which
credits any CI matrix - exactly the narrowing the check exists to catch.

## Decision

The reader returns the floor Ruby would assign, or says it cannot read it -
within the known limits below, which it cannot see. "Could not read" is
missing evidence, never "no floor".

- Every live line mentioning `required_ruby_version` must be a complete
  assignment of string literals. Anything else - a constant, interpolation,
  a heredoc, a trailing comma, a next-line chain or operator - is unreadable.
  So is a mention after `__END__` or inside `=begin`, where a heredoc can make
  it code.
- Local files the gemspec loads are read too, for the forms Ruby resolves the
  same way every time: `require_relative`, `File.expand_path` from `__dir__`
  or `__FILE__`, and `File.dirname(__FILE__) + "/x"` or `__dir__ + "/x"` from
  the loading file; `load` and `./` paths from the root; a bare `require` when
  `lib/` holds it. Only `require_relative` and a joined path keep a leading
  `~` as written; the others expand it, as Ruby does. The path must be the
  whole argument - anything after it but a parenthesis, a modifier or a
  comment changes the path. Nested loads are followed four levels deep, each
  file read on its own as UTF-8, and only to regular files inside the
  repository reached without a symlink: Ruby places a linked file's own loads
  where the link sits, so a symlinked gemspec or loaded file is not followed.
- A load the reader cannot follow - a built path, one leaving the repository
  or passing through a symlink, a missing file, a path Ruby could not use -
  makes the floor unreadable,
  **unless the gemspec itself assigns a literal floor**. A floor found only in
  a followed file does not settle it.
- An exception in the reader must never be a quieter way to reach "no floor":
  a path Ruby could not use is an unfollowed load, and a file that cannot be
  read is unreadable. A detector that still crashes is a discovery failure,
  which ADR-012 makes block the run rather than drop the facts.

## Known limits

These are not followed, and each can still read as "no floor" or as a floor
higher than Ruby's:

- A load not at the start of a statement: `begin require "x"`, `do |s|
  require_relative "x"`, `defined?(X) or require "x"`.
- A `require` of a name found through a `$LOAD_PATH` entry other than `lib/`.
- `eval`/`module_eval` of a file's text, and `Gem::Specification.load` of a
  base gemspec - the platform-variant pattern.
- An unfollowed load beside a literal floor in the gemspec, when that load
  lowers the floor afterwards - or when the gemspec's floor sits in a helper
  it never calls, which still settles it.
- A floor assigned inside a multi-line `if`, `unless` or `case`: the reader
  sees lines, not control flow, and reads it as unconditional.

Across 256 installed gemspecs, a reviewer compared the reader with
`Gem::Specification.load`: it never returned a higher floor than Ruby's, nor
"no floor" where Ruby had one. These shapes come from constructed fixtures
and one real precedent (fiddle's `module_eval` of its version file, which
sets no floor).

## Alternatives considered

- **Evaluate the gemspec.** Exact, and rejected: it runs repository code on
  the read-only path. It becomes possible once executed code has user and
  filesystem isolation (§12, ADR-010), and should then replace this reader,
  not sit beside it.
- **Treat every unfollowed load as unreadable, even beside a gemspec floor.**
  Closes the third limit above, but by a reviewer's count 27 of 256
  installed gemspecs - mostly the default gems'
  `rescue LoadError; require_relative "version"` fallback - would
  ask their owners to rewrite a floor that is already a plain literal. A
  literal floor in the gemspec is the owner's own statement; a later override
  by an unfollowed file needs deliberate indirection.
- **Treat any line that mentions `require`, `load` or `eval` as an unfollowed
  load.** Would close the first three limits, but prose in descriptions and
  heredocs mentions all three; the cost in false alarms was not measured, so it
  is left for a change that measures it.
- **Parse with Prism instead of reading lines.** Prism ships with Ruby 3.3+
  and parses without evaluating, so it would see heredocs, `__END__`,
  `=begin`, conditionals and loads anywhere in a statement as Ruby does, and
  would retire most of the line rules above. Not done here only because it
  replaces the reader rather than fixing it; it is the natural next step, and
  the specs pinning this reader's behaviour carry over as its acceptance
  tests.
- **Ignore loads, read only the gemspec.** The original reader. It read
  extralite, whose floor is set in a loaded file, as "no floor".
