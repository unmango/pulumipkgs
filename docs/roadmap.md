# Roadmap

This document tracks everything about `pulumipkgs` (see `docs/spec.md` for
the system design) that is staged, deferred, or still open.
It is expected to change as work lands; `docs/spec.md` is not.

## Non-goals

These are explicitly out of scope right now, not permanently:

- **Auto-merge.** The update automation opens pull requests but does not
  merge them; a person reviews and merges each one.
- **Full registry coverage.** Only packages listed in
  `data/supported-packages.json` are built, regardless of what else the
  Pulumi registry publishes.
- **Mandatory multi-language SDKs.** `passthru.sdks.python` is the only SDK
  every package is expected to support; other languages are added
  per-package, opportunistically.
- **Validation beyond build-only.** CI only checks that packages build.
  nixpkgs' `testResourceSchema` and `pulumiTestHook`, reused directly from
  nixpkgs (see spec §2), are available in the scope but aren't wired into
  any workflow.
- **Non-Go, non-GitHub-release providers.** The spec's package convention
  assumes a `buildGoModule`-shaped source tree fetched via
  `fetchFromGitHub`. Providers that don't fit this (different language,
  different distribution mechanism) aren't yet covered by a documented
  convention.

## Follow-ups

- **Shrink or remove the allowlist.** `data/supported-packages.json` is
  meant to grow, and eventually stop being a gate at all, once discovery
  and per-package onboarding are routine enough to not need manual
  curation.
- **Revisit auto-merge.** Once the update automation has a track record,
  consider merging automatically on green CI for at least a subset of
  low-risk packages, to reduce the human-review step's exposure against
  the 24h freshness target.
- **Wire up deeper validation.** Use nixpkgs' `testResourceSchema` (and
  possibly `pulumiTestHook`) in `ci.yml` once build-only checks have proven
  reliable, to catch schema/version mismatches that a bare build wouldn't.
- **Expand SDK language coverage.** Add `<lang>Args` support for languages
  beyond Python to this repo's `mkPulumiPackage` wrapper, following the same
  pattern as upstream's `mkPythonPackage`. Node.js is done (`nodejsArgs`,
  exercised by `pulumiPackages.github`); Go, .NET, and Java are still open.
- **Support non-Go providers.** Document (and implement) a second package
  convention for providers that aren't Go-based or aren't distributed via
  GitHub releases, so `data/supported-packages.json` isn't implicitly
  limited to one provider shape.
- **Measure the 24h target.** Once the update workflow and CI are running
  for real, confirm the chosen cron interval actually holds the 24h
  freshness goal in practice, accounting for actual PR review latency, and
  adjust the interval (or reconsider auto-merge) if it doesn't.
