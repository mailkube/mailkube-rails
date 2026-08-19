# Engineering Standards: SOLID · DRY · KISS · Coverage · Docs

These are **enforced by CI** — a PR that violates them cannot merge. This file tells you the exact
thresholds and how to satisfy each gate locally *before* pushing.

## The gates

| Gate | Rule | Enforced by |
|---|---|---|
| **Coverage** | ≥ 90% line **and branch** | `simplecov` in `spec/spec_helper.rb` (the `test` CI job) |
| **DRY** | ≤ 1% duplicated code | `jscpd` (the `dry` CI job) |
| **KISS** | cyclomatic complexity ≤ 10 per method | `rubocop` `Metrics/CyclomaticComplexity` (the `test` CI job) |
| **Documentation** | every class + public method has a YARD comment | `rubocop` `Style/Documentation` + `Style/DocumentationMethod` |
| **SOLID** | see below — approximated by analysis + review | `rubocop` metrics + `steep` + PR checklist |
| **Typing** | signatures coherent, and matched by the implementation | `rbs validate` + `steep check` (the `test` CI job) |
| **Formatting** | rubocop clean | `rubocop` (the `test` CI job) |

> **`Style/DocumentationMethod` is enabled here and is not in the SDK's config.** The SDK gets away
> without it because its public surface is small and every method carries YARD already. This gem's
> surface is mostly module functions, which that cop is the only thing that covers, so leaving it
> off would mean the documentation pillar was declared and not enforced.

> **Both halves of the type gate run, and neither is sufficient alone.** `rbs validate` proves the
> signatures are internally coherent but never loads `lib/`, so it passes a `sig/` describing
> methods that do not exist. `steep check` is what compares the two.

## Run the gates locally

```bash
bundle exec rake                                       # rubocop + rbs + steep + rspec, in one shot
bundle exec rubocop                                    # style, complexity (KISS), docs
bundle exec rake rbs                                   # signatures are internally coherent
bundle exec steep check                                # implementation matches the signatures
bundle exec rspec                                      # specs + coverage gate
npx --yes jscpd@4 --config .jscpd.json .               # duplication (DRY) gate
./scripts/check-rule-index.sh                          # every .rules/*.md indexed in AGENTS.md
```

`pre-commit run --all-files` runs the rubocop + jscpd hooks in one shot.

**Run them against more than one Rails major before pushing anything that touches the delivery
method or the payload mapping.** CI does; locally you get whatever Bundler last resolved, and the
surprises live in ActionMailer's internals rather than in its public API. `RAILS_VERSION=7.2 bundle
install` switches the axis, and `DEPENDENCY_FLOOR=1 bundle install` resolves everything down to the
gemspec's declared lower bounds.

## SOLID, concretely (paradigm-neutral guidance)

SOLID is not a single analyzer rule; keep these in mind and confirm them in the PR checklist:

- **S**ingle responsibility — a class/method does one thing; if you need "and" to describe it, split it.
- **O**pen/closed — extend via new classes/strategies, not by editing stable call sites.
- **L**iskov — subtypes honor their base's contract (types, exceptions, invariants).
- **I**nterface segregation — depend on the one verb you call, not on a whole object's surface.
- **D**ependency inversion — depend on an injected collaborator at I/O boundaries, not on a constant.

In this gem specifically, the single-responsibility line is drawn by
`.rules/INTEGRATION_CONTRACT.md`: one payload module, one config module, and no third place that
knows how to build either. When a change wants to add one, that is the rule it is arguing with.

## Requesting a waiver

If a threshold is genuinely wrong for a specific spot, add a **scoped, commented** ignore
(`# rubocop:disable Metrics/AbcSize` with a reason, closed by a matching `:enable`) and call it out
in the PR. Blanket relaxations (lowering the coverage threshold, disabling a department globally,
excluding a file from `steep`) require maintainer sign-off.
