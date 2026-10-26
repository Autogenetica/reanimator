# Releasing

Releases are **manual on purpose**. Nothing is published as a side effect of a
merge, and no long-lived credential is stored anywhere: publishing uses RubyGems
[trusted publishing](https://guides.rubygems.org/trusted-publishing/), which
exchanges a short-lived OIDC token at release time.

## One-time setup

1. On RubyGems.org, open the gem's **Trusted publishers** page and add a GitHub
   Actions publisher with:

   | Field | Value |
   | --- | --- |
   | Repository owner | `codenamev` |
   | Repository name | `reanimator` |
   | Workflow filename | `release.yml` |
   | Environment | *(leave empty)* |

   For a gem that has never been published, add it as a **pending** trusted
   publisher — that is what authorizes the very first push.

2. If you set an Environment on RubyGems.org, add the matching
   `environment: <name>` key to the `release` job in
   `.github/workflows/release.yml`. The two must agree or the OIDC exchange is
   rejected.

Nothing else is needed. There is no `RUBYGEMS_API_KEY` secret to create, rotate,
or leak — which is the point.

## Cutting a release

1. Move the `[Unreleased]` entries in `CHANGELOG.md` under a new
   `## [X.Y.Z] - YYYY-MM-DD` heading, leaving `[Unreleased]` empty above it.
2. Bump `Reanimator::VERSION` in `lib/reanimator/version.rb`.
3. Open a pull request with those two changes, get CI green, and merge it.
4. Run the **Release** workflow from the Actions tab against `main`.

The workflow runs `bundle exec rake` first and stops there if specs or
StandardRB fail. Only then does `rubygems/release-gem` run `rake release`, which
builds the gem, tags the commit, pushes the tag, and pushes the gem.

## If a release fails partway

`rake release` pushes the git tag before it pushes the gem, so a failure at the
RubyGems step leaves a tag with no published gem. Delete the tag locally and on
the remote, fix the cause, and run the workflow again:

```console
$ git tag -d vX.Y.Z && git push origin :refs/tags/vX.Y.Z
```

Never re-point an existing tag at a different commit — a published version is a
promise about one exact tree.
