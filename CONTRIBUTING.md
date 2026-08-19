# Contributing to mailkube-rails

Thanks for helping improve **mailkube-rails**, the Rails integration for
[mailkube](https://mailkube.com).
Contributions of all kinds are welcome: bug reports, fixes, docs, and features.

By contributing you agree that your contributions are licensed under the project's
[Apache License 2.0](LICENSE) (inbound = outbound). **No CLA and no sign-off are required.**
Please also read our [Code of Conduct](CODE_OF_CONDUCT.md).

## Development setup

Requires Ruby 3.4+ and Node.js (for the `jscpd` duplication check).

```bash
git clone https://github.com/mailkube/mailkube-rails
cd mailkube-rails

bundle install
pre-commit install                            # rubocop + jscpd hooks
pre-commit install --hook-type commit-msg     # Conventional Commits hook
```

There is no `Gemfile.lock` in the repository and there should not be: this is a library, so every
consumer resolves its own versions and CI must resolve fresh to mean anything.

## Quality gates

Every change must pass the same checks CI runs (see [.rules/SOLID_DRY_KISS.md](.rules/SOLID_DRY_KISS.md)):

```bash
bundle exec rake                                       # rubocop + rbs + steep + rspec, in one shot
bundle exec rubocop                                    # style, complexity (KISS), docs
bundle exec rake rbs                                   # signatures are internally coherent
bundle exec steep check                                # implementation matches the signatures
bundle exec rspec                                      # specs + 90% line and branch coverage
npx --yes jscpd@4 --config .jscpd.json .               # duplication (DRY) gate, blocks at > 1%
./scripts/check-rule-index.sh                          # every .rules/*.md indexed in AGENTS.md
```

**Run the suite against more than one Rails major** before pushing anything that touches the
delivery method or the payload mapping. CI runs a matrix; locally you get whatever Bundler last
resolved, and the surprises live in ActionMailer's internals rather than in its public API:

```bash
RAILS_VERSION=7.2 bundle install && RAILS_VERSION=7.2 bundle exec rspec
```

`DEPENDENCY_FLOOR=1 bundle install` resolves every runtime dependency down to the oldest version
the gemspec allows, which is what the `floor` CI job does.

This gem wraps an SDK, so there is one more thing to know before changing behaviour: **the
capability has to exist in the `mailkube` gem first.** If it does not, the change
starts in that repository, not this one. See [.rules/INTEGRATION_CONTRACT.md](.rules/INTEGRATION_CONTRACT.md).

## Branches

`develop` is the integration branch: open pull requests against it, and CI runs on every push to
it. `main` is the release branch — merging `develop` into it is what cuts a version, so nothing
lands there except through that merge. See [.rules/RELEASE.md](.rules/RELEASE.md).

Dependency updates target `develop` for the same reason. Their configuration names the branch
explicitly, and a branch that does not resolve produces no pull requests at all, with no error —
so if updates go quiet, check that `develop` still exists before looking anywhere else.

## Commit & PR conventions

This project follows **[Conventional Commits](https://www.conventionalcommits.org/)**. A CI check
named `PR-title` enforces the **PR title** (PRs are **squash-merged** using it), and it drives
releases: only
`feat:`, `fix:`, and `perf:` cut a new version. See [.rules/RELEASE.md](.rules/RELEASE.md).

Suggested scopes: `delivery`, `webhooks`, `config`, `ci`, `deps`, `docs`.

```
feat(delivery): map inline attachments
fix(payload): keep display names on reply-to addresses
docs: document the webhook route
```

## Reporting bugs / requesting features

Open an issue using the templates. For **security vulnerabilities**, do not open a public
issue — follow [SECURITY.md](SECURITY.md) instead.
