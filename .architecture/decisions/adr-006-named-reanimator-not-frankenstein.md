# ADR-006: Named Reanimator, not Frankenstein

- Status: Accepted
- Date: 2026-10-25

## Context

The project was built under the name Frankenstein, which carried the idea well:
something dead or dying, brought back and kept alive, with a character behind it
that marketing could use.

Two problems surfaced at the point of publishing.

The gem name `frankenstein` is taken on RubyGems by an actively downloaded
Prometheus instrumentation library (35,424 downloads, last released 2020), owned
by someone else. A gem cannot be published under a name you do not hold, so
0.1.0 could not ship as it stood.

The second problem is subtler and mattered more. Frankenstein describes a single
dramatic act of revival. That is not what this tool does. Repositories do not
die in a lightning strike; they rot quietly while nobody is looking, and the
tool's actual job is the continuous, read-only proof that they have not. The
name promised a resurrection and the product delivers surveillance of decay.

Alternatives considered and rejected:

- `frankenstein-repo` and similar suffixes. Reads as a namespace collision
  workaround rather than a decision.
- `dr-frankenstein`. Keeps the word and the character for a three-line diff, and
  is pedantically the *correct* name (Frankenstein is the doctor, not the
  creature). Rejected only because the full rename was wanted.
- `idunn`. The Norse keeper whose apples hold off the gods' aging; when she is
  taken, they begin to wither immediately. The most accurate metaphor found —
  decay beginning the moment the keeper looks away — and the closest fit to a
  read-only-first posture, since Idunn prevents death rather than reversing it.
  Rejected because it has to be taught: the myth is not widely known and the
  spelling is unstable (`idunn`/`idun`/`iduna`).
- `asclepius`. Raised the dead, and brings the Rod of Asclepius with him — a
  world-famous public-domain mark, free. Rejected on spelling: all three
  plausible spellings were available on RubyGems, which is itself the evidence
  that nobody can spell it, and this is a name people type daily.
- `nightingale`. Proved health by *measurement* rather than assertion, which is
  precisely this product's thesis. Unavailable; actively maintained gem.

## Decision

The product is **Reanimator**: gem `reanimator`, module `Reanimator`, command
`reanimator`, contract file `.reanimator.yml`, snapshot file
`.reanimator-snapshot.json`, environment variables `REANIMATOR_*`.

The deciding argument was that a name requiring explanation is a tax paid
forever, by every reader, in every conversation. `reanimator` says what the tool
does with no mythology to teach, and keeps the mad-science register the original
name had. H.P. Lovecraft's 1922 "Herbert West — Reanimator" is public domain;
the 1985 film's visual identity is not, so project artwork is original.

The rename was applied as a re-runnable script rather than a hand-made diff,
because it touches nearly every file and therefore conflicts with anything in
flight. Re-running a substitution on a moved base is cheaper and less error-prone
than resolving those conflicts by hand.

## Consequences

- Any contract file or recorded snapshot written under the old name is not read:
  the filenames changed. Nothing is published yet, so no user is affected, and
  this is the last moment at which that is true for free.
- The repository itself must be renamed on GitHub for the URLs in the gemspec
  and README to resolve. GitHub redirects the old path permanently afterwards,
  so existing links and clones keep working.
- `.reanimator.yml` is a protected path on the safety floor, as its predecessor
  was; the floor's guarantee is unchanged, only its spelling.
