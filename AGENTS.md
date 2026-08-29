# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## What this is

A Nix flake exposing `pulumiPackages`: Pulumi resource providers, language runtimes, and source-based (component) plugins.
It mirrors the shape of nixpkgs' own `pulumiPackages` scope, expands it toward the Pulumi registry, and keeps versions current through automation.

`docs/spec.md` is the authoritative design document and describes the system as designed.
`docs/roadmap.md` tracks non-goals, deferred work, and open follow-ups.
Read the relevant spec section before changing structure; the spec is meant to be stable, the roadmap is not.

## Commands

Note: `make` is shadowed by a zsh autoload stub in agent shells; use `command make`, or run the `nix` commands directly.

```bash
nix build .#                      # build the joined `default` environment (make build)
nix build .#<name> -L             # build one package, e.g. .#pulumi-dotnet or .#github
nix flake check -L                # build every package + every passthru test (make check)
nix build .#checks.<system>.pulumiPackages-pulumi-dotnet-genSdk   # run a single test
nix fmt                           # treefmt: nixfmt, mdformat, shellcheck, actionlint (make fmt)
nix develop                       # devshell with gh, jq, nix-update, nixfmt
nix flake update                  # bump flake inputs (make update)
./scripts/update.sh               # run the update automation locally (needs gh auth)
```

There is no unit test framework.
"Tests" are Nix derivations in a package's `passthru.tests`, surfaced as flake checks named `pulumiPackages-<package>-<test>`.

## Architecture

`flake.nix` calls `pkgs/default.nix` to build the scope, then exposes it four ways: `overlays.default`, `packages.<system>` (flattened, plus a `symlinkJoin`ed `default`), `legacyPackages.<system>.pulumiPackages`, and `checks.<system>`.

`pkgs/default.nix` builds the scope with `makeScopeWithSplicing'` + `packagesFromDirectoryRecursive` over three directories, all merged into one flat attribute set.
Adding `pkgs/<kind>/<name>/package.nix` is all that is needed to add a package; nothing lists packages anywhere else.
The scope's `extra` injects `mkPulumiPackage` and `mkTerraformBridgeProvider` (from the `pulumi2nix` flake input), `mkComponentPackage` (local), and `testResourceSchema`/`pulumiTestHook` (`callPackage`d by path out of the `nixpkgs` input).

Three distinct package conventions live in that one flat scope:

1. **`pkgs/plugins/<name>/`** (spec §4): resource providers, exposed as `pulumiPackages.<name>`.
   Use `mkPulumiPackage` for native gen tools (`<cmdGen> schema.json --version <v>`; it asserts you pass your own `postConfigure`) and `mkTerraformBridgeProvider` for tfgen tools (`<cmdGen> schema`; the default `postConfigure` usually suffices).
   Only these are governed by `data/supported-packages.json` and the registry half of `scripts/update.sh`.
1. **`pkgs/languages/pulumi-<lang>/`** (spec §4a): language runtimes (`pulumi-language-<lang>`), exposed as `pulumiPackages.pulumi-<lang>`.
   Three shapes: re-exports that just `callPackage` nixpkgs' file by `nixpkgsPath` (go, nodejs, python, bun; no local pins); bespoke `buildGoModule` builds with local pins (dotnet, java, yaml); and community hosts under non-`pulumi` orgs (rust, gestalt).
1. **`pkgs/components/<name>/`** (spec §4b): source-based plugins built by `pkgs/mk-component-package.nix`, no compile step and no `mainProgram`; `$out` is the plugin source tree with `node_modules` vendored offline via `fetchYarnDeps`/`yarnConfigHook`.

## Conventions that are easy to get wrong

Nothing here reimplements what nixpkgs or `pulumi2nix` already provides.
If nixpkgs ships the file, `callPackage` it by path through `nixpkgsPath`; if a builder shape is needed, it belongs in `pulumi2nix.lib`, not in this tree.

Community language hosts (spec §4a) must name their upstream and author in a header comment and install upstream's license text to `$out/share/doc/<pname>/LICENSE`.
`meta.maintainers` is not that credit and is not set by any package here.

Two packages installing the same binary name cannot both be in the joined `packages.default`; add the loser to `joinConflicts` in `flake.nix` with a comment saying why.
Both still get built by `checks`.

Only add a `passthru.tests` entry where building the package does not prove the thing that matters (see `pulumi-dotnet`'s `genSdk` test, which is the only reason the offline-logo patch stays honest).
`testExclusions` in `flake.nix` is strictly for tests inherited from a nixpkgs re-export that fail for reasons unrelated to this flake; a locally written failing test is a bug to fix, not to list.

Where a build deviates from the obvious (sandbox network, submodules, patched codegen, `doCheck = false`), the existing packages explain why in a comment.
Match that density.

## Update automation

`scripts/update.sh` (run every 6 hours by `.github/workflows/update.yml`) has two independent loops:

- Providers: diff each `data/supported-packages.json` entry's pinned version against the Pulumi registry YAML.
  `"autoUpdate": false` reports the drift but opens no PR, for packages whose `rev` is not derivable from `version`.
- Language runtimes: diff each `pkgs/languages/pulumi-*` local `version` pin against GitHub releases, reading `owner`/`repo` from the package's own `fetchFromGitHub`.
  Re-exports (no local pin) and `unstable-<date>` pins are skipped.

Both loops bump via `nix-update --flake <name> --version=<v> --override-filename <path>`.
Both flags are load-bearing: there is no `default.nix` to import, and `src` positions resolve into the `pulumi2nix` store path rather than this repo.
Each package is attempted independently, each success is its own PR, and the run exits non-zero only if something actually failed (a needed manual bump does not turn it red).
Every PR gets auto-merge enabled, so `main`'s required `build` check is what gates a bump.
The workflow runs on the `UPDATE_TOKEN` PAT secret, not `GITHUB_TOKEN`: `main`'s ruleset requires attributed commits and a passing check, and `GITHUB_TOKEN` gives neither.

`.github/workflows/ci.yml` builds only the packages whose `pkgs/plugins/**` or `pkgs/components/**` files changed; any change elsewhere falls back to a full `nix flake check`.

## Style

Markdown files put one sentence per line.
Nix is formatted by `nixfmt` via `nix fmt`; run it before committing.
