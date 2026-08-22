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

- **Drop the local `mkTerraformBridgeProvider` composition once upstream
  fixes it.** `pulumi2nix`'s own `mkTerraformBridgeProvider` has no
  `<lang>Args`/SDK layering (unlike `mkPulumiPackage`); passing it
  `nodejsArgs` (as `pulumiPackages.github` does) fails outright rather than
  degrading gracefully. `pkgs/default.nix`'s `mkTerraformBridgeProvider`
  works around this by composing `mkPulumiPackage` (build + SDK layering)
  with a `passthru.schema` swap for the tfgen-flavored schema, mirroring
  what `mkTerraformBridgeProvider` does internally. Filed upstream as
  [UnstoppableMango/pulumi2nix#28](https://github.com/UnstoppableMango/pulumi2nix/issues/28);
  once resolved there, this repo's composition can likely be dropped in
  favor of calling `pulumi2nixLib.mkTerraformBridgeProvider` directly again.
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
- **Expand SDK language coverage.** `<lang>Args` support beyond Python now
  comes from the `pulumi2nix` flake input rather than a local wrapper.
  Node.js is exercised (`nodejsArgs`, `pulumiPackages.github`); Go
  (`goArgs`) and .NET (`dotnetArgs`) builders exist in `pulumi2nix.lib` and
  are unblocked, but not yet exercised by any package in this repo — no
  `pkgs/plugins/<name>/package.nix` sets `goArgs`/`dotnetArgs` yet. Java
  still has no builder upstream either. This is about a *provider's*
  generated SDK bindings (`passthru.sdks.<lang>`) — a different axis from
  language runtime packages (`pulumiPackages.pulumi-<lang>`, the CLI's
  language-host plugin, spec §4a) below; don't conflate the two.
- **Automate language runtime version bumps.** `pulumiPackages.pulumi-dotnet`,
  `pulumi-java`, and `pulumi-yaml` (spec §4a) have manually-pinned
  `version`/`hash`/`vendorHash`, unlike resource providers' auto-PR flow
  (§5) — there's no registry-diff automation for them yet. `pulumi-go`,
  `pulumi-nodejs`, `pulumi-python`, and `pulumi-bun` don't need this: they
  track whatever version nixpkgs' own `pulumi` package pins.
  `pulumi2nix.lib.pulumiLanguageDotnet` provides the same binary but is
  currently pinned to an older `pulumi-dotnet` (3.110.0) than this repo's
  own manual pin (3.112.1), so switching `pulumi-dotnet` over to it today
  would be a downgrade — revisit once `pulumi2nix` exposes a way to
  override the pinned package/version (requested upstream) or its own pin
  catches up.
- **Support non-Go providers.** Document (and implement) a second package
  convention for providers that aren't Go-based or aren't distributed via
  GitHub releases, so `data/supported-packages.json` isn't implicitly
  limited to one provider shape.
- **Measure the 24h target.** Once the update workflow and CI are running
  for real, confirm the chosen cron interval actually holds the 24h
  freshness goal in practice, accounting for actual PR review latency, and
  adjust the interval (or reconsider auto-merge) if it doesn't.
