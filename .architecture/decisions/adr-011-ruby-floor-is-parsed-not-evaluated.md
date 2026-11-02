# ADR-011: A gem's Ruby floor is parsed, never evaluated

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

The first readers worked line by line. Fourteen adversarial reviews kept
finding the same shape: a way of writing a floor or a load that a line
reader missed - a second statement after `;`, a heredoc that looked like
`__END__`, a path with a suffix, a value on the next line - which read as
"no floor" and credited any CI matrix, exactly the narrowing the check exists
to catch. Each fix was a new rule about how lines look; each review found the
next one.

## Decision

The gemspec, and every local file it loads, is **parsed with Prism** - the
parser Ruby itself ships - and never run. A parse sees what Ruby sees, so
statements after `;`, modifiers, heredocs, `=begin` and `__END__` mean what
they mean to Ruby.

- **Every floor assignment counts.** Wherever an assignment of
  `required_ruby_version` appears - a branch Ruby may skip, a helper never
  called - it is read, and the lowest floor wins downstream. Reading an
  assignment Ruby would not run can only make the check stricter; what must
  never happen is missing one.
- **Its value must be literal:** a string, an array of strings, `.freeze` on
  one, or `Gem::Requirement.new` of them. Anything else - a constant, an
  interpolation, a method call on the literal - makes the floor unreadable.
- **Any other route to the floor is unreadable:** a symbol or string naming
  it (`send`, `public_send`, `instance_variable_set`), `||=`, `&&=` and other
  operator writes, a multiple assignment, a direct write of
  `@required_ruby_version`, a method defined with the floor's name, and code
  run from a string (`eval`, `binding.eval`, `instance_eval("...")`) - which
  could set any floor, so not even a literal floor in the gemspec settles it.
  Prose that merely mentions the floor is just a string.
- **Every load anywhere is followed or reported.** `require_relative` resolves
  from the loading file; `load`, `require` and `autoload` from `lib/` (which
  a gem puts on its load path) or the root - unless the file puts anything
  else on the load path, when a bare name could lead elsewhere and is not
  followed; `File.expand_path` from `__dir__` or
  `__FILE__`, and `__dir__`/`File.dirname(__FILE__) + "/x"`, from the loading
  file. `~` is kept or expanded as Ruby does for each. Nested loads are
  followed four levels deep, each file read on its own as UTF-8, only to
  regular files inside the repository reached without a symlink - Ruby
  places a linked file's own loads by rules that differ between the gemspec
  and what it loads, and Reanimator does not guess which.
- **A load it cannot follow** - a path built at runtime, one outside the
  repository or through a symlink, a missing file, a load reached by name
  (`send(:require_relative, ...)`), `Gem::Specification.load` of another
  gemspec, a bare `require` of a name that is in `lib/` but not exactly -
  makes the floor unreadable, **unless
  the gemspec itself assigns a literal floor**, the owner's own statement,
  which then settles it.
- **A file that does not parse, or cannot be read,** makes the floor
  unreadable, and so does one over 256 KB or nested over 1,000 brackets
  deep: past that, parsing can exhaust the stack, and an overflow repeated
  in one process can kill it outright. A detector that still crashes is a discovery failure, which
  ADR-012 makes block the run rather than drop the facts.

Unreadable is reported as missing evidence asking for a literal floor, never
as "no floor".

## Known limits

- An unfollowed load beside a literal floor in the gemspec, when that load
  lowers the floor - or when the gemspec's floor sits in a helper it never
  calls, which still settles it.
- A route to the floor through a name the parse cannot see - any computed
  name (`public_send(var)`, an interpolated or concatenated symbol), the
  requirement object mutated through its getter, `ObjectSpace`, or
  `Gem::Specification` reopened in a file the gemspec does not load. Each
  needs deliberate indirection.

Across 1,397 installed gemspecs (the same gems under several Rubies), the
parser was compared with `Gem::Specification.load`: it never returned a
higher floor than Ruby's nor "no floor" where Ruby had one. Six gems read
as unreadable: the five the line reader also could not read, and fiddle,
which `module_eval`s its version file beside a literal floor. A reviewer ran
the same cases under Prism 1.0, 1.9 and 2.1 with identical readings; the
dependency allows `< 3` on that basis.

## Alternatives considered

- **Evaluate the gemspec.** Exact, and rejected: it runs repository code on
  the read-only path. It becomes possible once executed code has user and
  filesystem isolation (§12, ADR-010), and should then replace this reader.
- **Read line by line.** The approach this ADR replaces. It had no new
  dependency, and it was wrong in a new way each review.
- **Prism as bundled with Ruby.** Ruby 3.3 ships Prism 0.19, whose API
  predates 1.0, so the gem depends on `prism >= 1.0, < 3` instead.
- **Treat every unfollowed load as unreadable, even beside a gemspec floor.**
  Closes the first limit, but by a reviewer's count 27 of 256 installed
  gemspecs - mostly the default gems' `rescue LoadError; require_relative
  "version"` fallback - would ask their owners to rewrite a floor that is
  already a plain literal.
- **Credit the standard `$LOAD_PATH.unshift` only by assuming it.** Treating
  any load-path change as unfollowed made 22 of 260 installed gems
  unreadable, nearly all for the idiom that adds `lib/`. Only adding
  something other than the repository's `lib/` counts.
- **Treat a floor in a branch as unreadable.** Unnecessary: the lowest floor
  wins, so reading a branch Ruby skips can only be stricter.
