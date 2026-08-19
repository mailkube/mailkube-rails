# Project Rules

`mailkube-rails` is a public (Apache-2.0) ActionMailer delivery method for
mailkube, distributed as the `mailkube-rails` gem on rubygems.org. It wraps
the `mailkube` gem and talks to no API of its own. Load the relevant rule file from
`.rules/` based on the task.

## Rule Index

> **Index every rule (required).** Every file in `.rules/` MUST have a row in the table below. When you
> add or rename a `.rules/` file, add or update its row in the **same change** — an unindexed rule is
> invisible, because this index is what drives progressive disclosure. The `docs` CI job (`scripts/check-rule-index.sh`)
> fails the build if `.rules/` and this index drift. This convention holds for every mailkube repo.

| Rule File | Load When |
|---|---|
| `.rules/SOLID_DRY_KISS.md` | Writing or changing any code — the enforced engineering standards (SOLID, DRY, KISS, coverage, docs) and how to run each gate locally. |
| `.rules/INTEGRATION_CONTRACT.md` | Touching the delivery method, the payload mapping, the settings surface, the webhook endpoint, or anything tempted to talk to the API directly: the decisions every mailkube framework integration implements identically. Shared verbatim across every integration; changes are made centrally. |
| `.rules/RAILS_INTEGRATION.md` | The same tasks, for the **Rails realization**: the file-to-responsibility map, the `::Rails` naming trap, why the Railtie ordering is load-bearing, the delivery-method protocol as `mail` actually invokes it, and the two recorded deviations. |
| `.rules/SDK_CONTRACT.md` | Understanding what the SDK underneath guarantees — config resolution, errors, pagination, webhook signatures — before assuming this gem has to do any of it. Shared verbatim across every mailkube repo; changes are made centrally. |
| `.rules/RELEASE.md` | Touching `release.yml`, `.releaserc.json`, `version.rb`, versioning, or the RubyGems publish flow. |
| `.rules/CI_GATES.md` | Adding, removing or weakening a CI job, or when a release fails after the tag was already pushed: why the publish-readiness, dependency-floor, example-compilation and release-permission gates exist. Shared verbatim across every mailkube repo; changes are made centrally. |

## Key Conventions (always apply)

- **This is an adapter, not an SDK.** No HTTP client, no request serialization, no HMAC, no error
  envelope parsing. If you are writing one of those, you are in the wrong repository.
- **Always write `::Rails`** for the framework. Inside this namespace the bare constant is
  this gem, and Ruby resolves the wrong one silently.
- **One payload module and one config module** — `payload.rb` and `config.rb`. Every entry point
  calls them; nothing else maps a message or builds a client.
- **An unset setting is omitted, never passed as nil**, so the SDK's own environment fallbacks
  survive.
- **The version is never a literal.** `version.rb` is the single source; the gemspec and
  `Config.user_agent_suffix` both read it.
- **No models, no migrations, no tables.** This gem persists nothing, which is also what keeps the
  spec suite free of a database and of a host application.
- **SDK errors are translated at the boundary** into `DeliveryError`, because `retry_on` and
  `discard_on` have to name a class this gem owns.
- **Webhooks verify against `request.raw_post`.** Never a parsed-then-re-encoded body.
- **Synchronous throughout**, inherited from the delivery-method protocol. Never start an event
  loop; an async entry point would be a new class alongside.
- **`frozen_string_literal: true`** in every file; rubocop clean; `steep check` clean.
- Coverage ≥ 90% line and branch; complexity ≤ 10; jscpd ≤ 1%.
- YARD comments on every class and public method; update them when behaviour changes.
- **Conventional Commits** for PR titles — only `feat:`, `fix:` and `perf:` release.
- **No `CHANGELOG.md`**: the GitHub Release notes are the changelog.
- **No `Gemfile.lock`**: this is a library, so consumers resolve their own versions.
- **No secrets in the repo.** Local configuration goes in a git-ignored `.env`.
- Keep `README.md` current: it is the only documentation of the wiring, because this gem ships no
  `examples/`.
