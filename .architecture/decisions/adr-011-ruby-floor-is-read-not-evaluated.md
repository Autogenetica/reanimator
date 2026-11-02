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

The reader returns the floor Ruby would assign, or says it cannot read it. It
never guesses, and "could not read" is missing evidence, never "no floor".

- Every live line mentioning `required_ruby_version` must be a complete
  assignment of string literals. Anything else - a constant, interpolation,
  a heredoc, a trailing comma, a next-line chain or operator - is unreadable.
  So is a mention after `__END__` or inside `=begin`, where a heredoc can make
  it code.
- Local files the gemspec loads are read too, resolved as Ruby resolves them:
  `require_relative` and `File.expand_path`/`File.dirname(__FILE__) +` from
  the loading file, `load` and `./` paths from the root, a bare `require` when
  `lib/` holds it. Nested loads are followed four levels deep, only to real
  paths inside the repository, each file read on its own as UTF-8.
- A load the reader cannot follow - a built path, one leaving the repository,
  a missing file, a path Ruby could not use - makes the floor unreadable,
  **unless the gemspec itself assigns a literal floor**. A floor found only in
  a followed file does not settle it.
- An exception in the reader must never be a quieter way to reach "no floor":
  a path Ruby could not use is an unfollowed load, a file that cannot be read
  is unreadable, and a detector that still crashes is a discovery failure,
  which must block rather than drop the facts.

## Known limits

These are not followed, and each can still read as "no floor" or as a floor
higher than Ruby's:

- A load not at the start of a statement: `begin require "x"`, `do |s|
  require_relative "x"`, `defined?(X) or require "x"`.
- A `require` of a name found through a `$LOAD_PATH` entry other than `lib/`.
- `eval`/`module_eval` of a file's text, and `Gem::Specification.load` of a
  base gemspec - the platform-variant pattern.
- An unfollowed load beside a literal floor in the gemspec, when that load
  lowers the floor afterwards.

On installed gems, the reader matches `Gem::Specification.load` or reports
unreadable for every gemspec checked; these shapes come from constructed
fixtures and one real precedent (fiddle's `module_eval` of its version file,
which sets no floor).

## Alternatives considered

- **Evaluate the gemspec.** Exact, and rejected: it runs repository code on
  the read-only path. It becomes possible once executed code has user and
  filesystem isolation (§12, ADR-010), and should then replace this reader,
  not sit beside it.
- **Treat every unfollowed load as unreadable, even beside a gemspec floor.**
  Closes the last limit above, but by the reviewers' count 27 of 256
  installed gemspecs - mostly the
  default gems' `rescue LoadError; require_relative "version"` fallback - would
  ask their owners to rewrite a floor that is already a plain literal. A
  literal floor in the gemspec is the owner's own statement; a later override
  by an unfollowed file needs deliberate indirection.
- **Treat any line that mentions `require`, `load` or `eval` as an unfollowed
  load.** Would close the first three limits, but prose in descriptions and
  heredocs mentions all three; the cost in false alarms was not measured, so it
  is left for a change that measures it.
- **Ignore loads, read only the gemspec.** The original reader. It read
  extralite, whose floor is set in a loaded file, as "no floor".
