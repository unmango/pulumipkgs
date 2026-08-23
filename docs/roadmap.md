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
  `pulumi-java`, `pulumi-yaml`, and `pulumi-gestalt` (spec §4a) have
  manually-pinned `version`/`hash`/`vendorHash`, unlike resource providers'
  auto-PR flow (§5) — there's no registry-diff automation for them yet. `pulumi-go`,
  `pulumi-nodejs`, `pulumi-python`, and `pulumi-bun` don't need this: they
  track whatever version nixpkgs' own `pulumi` package pins.
  `pulumi2nix.lib.pulumiLanguageDotnet` provides the same binary but is
  currently pinned to an older `pulumi-dotnet` (3.110.0) than this repo's
  own manual pin (3.112.1), so switching `pulumi-dotnet` over to it today
  would be a downgrade — revisit once `pulumi2nix` exposes a way to
  override the pinned package/version (requested upstream) or its own pin
  catches up.

- **Automate component package version bumps.**
  `pulumiPackages.pulumi-components` (spec §4b) is pinned by commit SHA —
  its upstream has no tagged releases — with manually-pinned
  `version`/`hash`/`yarnHash`, same situation as the language runtime
  follow-up above. There's no registry-diff automation for source-based
  plugins yet, and no registry entry to diff against even if there were.

- **Expand source-based plugin language support.** `mkComponentPackage`
  (spec §4b) only knows how to vendor Node.js/TypeScript dependencies
  (via `fetchYarnDeps`/`yarnConfigHook`). Python, Go, .NET, and Java are
  all languages Pulumi source-based plugins support; add vendoring for
  each as a package needing it comes up, mirroring how SDK language
  support is added opportunistically in §4.

- **Support non-Go providers.** Document (and implement) a second package
  convention for providers that aren't Go-based or aren't distributed via
  GitHub releases, so `data/supported-packages.json` isn't implicitly
  limited to one provider shape.

- **Give `pulumi-rust` a release-based pin.** `pulumiPackages.pulumi-rust`
  (spec §4a) tracks a commit as `unstable-<date>` because
  `pulumi-labs/pulumi-rust` has cut no tags yet, so §5a skips it entirely.
  Switch it to `tag = "v${version}"` once upstream releases, which also
  re-enables the automation for it with no change to `scripts/update.sh`.

- **Ship the Rust SDK crate.** `pulumi-rust` installs the `pulumi new`
  template, but the template's `Cargo.toml` reaches the `pulumi` crate
  through a relative path into a checkout, because the crate isn't published
  to crates.io. Until it is, the installed template is a starting point
  rather than something that builds as-is; packaging `sdk/rust/pulumi` and
  repointing the template at it is the fix, and needs a decision about where
  a Rust SDK belongs in this tree.

- **Revisit `pulumi-gestalt`.** Andrzej Ressel's upstream is archived, it is the only
  two-stage (Rust staticlib feeding a cgo Go build) package in the tree, and
  its `go.mod` needs a `postPatch` to drop a `replace` pointing at a commit
  that no longer exists upstream. It also duplicates `pulumi-rust`'s
  `pulumi-language-rust` binary, which is why `flake.nix` keeps it out of
  the joined `packages.default`. Drop it if it stops building against
  whatever rustc nixpkgs ships, rather than pinning a bespoke toolchain — and
  if it is dropped, say in the commit that it was their work, not that it
  was broken.

- **Measure the 24h target.** Once the update workflow and CI are running
  for real, confirm the chosen cron interval actually holds the 24h
  freshness goal in practice, accounting for actual PR review latency, and
  adjust the interval (or reconsider auto-merge) if it doesn't.
