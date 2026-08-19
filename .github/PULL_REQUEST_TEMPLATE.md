<!--
PR titles MUST follow Conventional Commits (e.g. `fix(client): ...`) — it is CI-enforced and
becomes the squash-merge commit message. Only feat/fix/perf trigger a release.
-->

## What

<!-- Describe the change in 1–2 sentences. -->

## Why

<!-- The user-visible problem this solves, or the motivation. -->

## Quality checklist

- [ ] `bundle exec rubocop` passes (complexity, docs, style)
- [ ] `bundle exec rake rbs` passes (the signatures are coherent)
- [ ] `bundle exec steep check` passes (the implementation matches them)
- [ ] `bundle exec rspec` passes at ≥ 90% line **and** branch coverage
- [ ] `npx jscpd --config .jscpd.json .` clean (no new duplication)
- [ ] Docs updated (`README.md`) if user-visible

## Engineering standards (SOLID / DRY / KISS)

- [ ] Single-responsibility: new/changed units do one thing; no god-methods
- [ ] No duplication introduced; shared logic extracted (DRY)
- [ ] Public classes and methods documented (YARD comments)
- [ ] Complexity within limit (no `rubocop:disable` complexity waivers added)
- [ ] Depends on abstractions at boundaries (DIP) — a new capability adds a seam, never widens one

## Notes

<!-- Optional: screenshots, follow-ups, breaking-change details. -->
