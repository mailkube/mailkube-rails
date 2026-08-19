# Release & Publishing

Load this when touching `release.yml`, `.releaserc.json`, versioning, or RubyGems publishing.

## The contract

1. **Conventional Commits drive the version.** On push to `main`, `semantic-release` reads the commit
   history since the last tag: `fix:` → patch, `feat:` → minor, `feat!:`/`BREAKING CHANGE:` → major.
   `perf:` also releases. Anything else (`chore`, `docs`, `ci`, `refactor`, `test`) does **not** release.
2. **It creates the tag `vX.Y.Z` and the GitHub Release, and writes nothing else.** No commit, no
   `CHANGELOG.md`, no version bump in the tree. See "Why nothing is committed back to `main`".
3. **`lib/mailkube/rails/version.rb` is the one version source, and it stays `0.0.0` in the
   repository.** `.releaserc.json`'s `prepareCmd` rewrites that line inside the release runner, and
   the gemspec reads the constant — so the built gem carries the real version and nothing is
   committed back. The **same** constant feeds `Config.user_agent_suffix`, which is what makes the
   User-Agent this gem reports impossible to drift from the version RubyGems serves.
4. **The gem is pushed from `publishCmd`**, over RubyGems OIDC trusted publishing. No API key is
   stored anywhere.

## Why nothing is committed back to `main`

`main` is covered by a ruleset requiring a pull request and the gated checks. A `chore(release):`
commit pushed straight to `main` by the workflow violates it, and the obvious fix does not exist:
**`github-actions[bot]` cannot be added to a ruleset bypass list.** Bypass is available to admins,
the maintain/write role, teams, GitHub Apps and Dependabot, and the built-in Actions identity is none
of those. Making the commit work would mean introducing a separate identity — a GitHub App or a
deploy key — purely to write a version number that the tag already carries.

So `.releaserc.json` loads neither `@semantic-release/git` nor `@semantic-release/changelog`. The
release writes one tag and one GitHub Release. **The generated release notes are the changelog**;
there is no `CHANGELOG.md` in this repo, and adding one back would reintroduce the commit.

## Required setup (one-time, per repo)

- GitHub **environment** `release` (Settings → Environments), with protection rules; the `release`
  job runs in it. It holds no secret: the RubyGems push is OIDC.
- **Register this repository as a RubyGems trusted publisher for the gem.** The gem does not exist
  yet at that point, so register a **pending** trusted publisher under your RubyGems profile: it
  reserves the name and converts on first push, so even the first release goes out over OIDC and no
  hand-rolled `gem push` is ever needed.
- The environment name in the trusted-publisher registration must match `release.yml`'s
  `environment:` **byte for byte**. A mismatch fails the push *after* the tag and the GitHub Release
  already exist, and semver forbids reusing the version.

## Do not

- Do not add a `CHANGELOG.md`, a `@semantic-release/git` plugin, or a second version literal
  anywhere, and do not move tags.
- Do not commit `Gemfile.lock` — this is a library; consumers resolve their own versions.
- Do not gate `release.yml` on anything weaker than the full `ci.yml` (`test` + `build` + `floor` +
  `forward-compat` + `dry` + `docs`).
- Do not use `rubygems/release-gem`. It runs `bundle exec rake release`, which refuses a dirty
  working tree and creates its own tag — and here the tree is dirty on purpose (`prepareCmd` just
  rewrote `version.rb`) and the tag already exists.
- Do not widen `spec.files` without re-reading the `build` job. It is the packaging manifest, and it
  deliberately excludes `sig/vendor/`: those are partial, hand-written Rails signatures, and
  publishing them would put them on the load path of anyone who types this gem.
- Do not raise `sdk_min_version` without checking what the integration actually calls. The floor is
  a promise about which SDK releases this gem works against, and the `floor` job is the only thing
  that tests it.
