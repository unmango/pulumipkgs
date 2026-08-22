# Specification

This document specifies the design of `pulumipkgs`: a Nix flake exposing a
package set of Pulumi provider plugins, structured to match the shape of
nixpkgs' own `pulumiPackages`, expanded to track the Pulumi registry, and
kept current through automation.

This document describes the system as designed.
It intentionally omits staged rollout, non-goals, and open questions; those live in `docs/roadmap.md`.

## 1. Overview

The flake produces `pulumiPackages`: an attribute set of Pulumi provider
plugin derivations, one per supported provider.
The attribute set is shaped as a Nix package-set scope, matching the
structure and builder conventions of nixpkgs' own `pkgs/by-name/pu/pulumi`.
The set of providers it covers is driven by the Pulumi registry, filtered
through an explicit allowlist (`data/supported-packages.json`).
An automated workflow keeps each provider's pinned version and content
hashes synchronized with upstream releases, submitting one pull request per
package update for human review.

## 2. Repository layout

```
flake.nix
pkgs/
  default.nix
  plugins/
    <name>/
      package.nix
  languages/
    pulumi-<lang>/
      package.nix
data/
  supported-packages.json
scripts/
  update.sh
.github/
  workflows/
    ci.yml
    update.yml
docs/
  spec.md
  roadmap.md
```

This is the target layout, not the current repo tree; it lands incrementally, see `docs/roadmap.md` for staging.

Nothing in this tree duplicates logic nixpkgs or `pulumi2nix` already
provides. Where nixpkgs' own `pkgs/by-name/pu/pulumi` ships a file that does
exactly what this flake needs, that file is referenced by path from the
`nixpkgs` flake input and called directly, rather than copied into this
repository. Where a provider needs a builder shape (native gen-tool binary,
Terraform-bridged binary, per-language SDK layering) rather than a single
file, that comes from the `pulumi2nix` flake input's `lib` instead of being
reimplemented here. A file exists under `pkgs/` only where its behavior
isn't available from either upstream as-is.

### `flake.nix`

Inputs: `nixpkgs`, `pulumi2nix`.

Outputs:

- `overlays.default`: a nixpkgs overlay that adds a `pulumiPackages`
  attribute to the final package set, in the same shape (attribute names,
  builder signature) as nixpkgs' own `pulumiPackages` scope. A consumer can
  apply this overlay to their own nixpkgs instantiation and get
  `pkgs.pulumiPackages.<name>` alongside every other package.
- `packages.<system>` / `legacyPackages.<system>.pulumiPackages`: the same
  scope, exposed directly from this flake for consumers who don't want to
  apply the overlay.
- `checks.<system>`: one check per package under `pulumiPackages`, each
  simply the package's own build (`nix flake check` therefore builds every
  package in the set).

### `pkgs/default.nix`

Builds the `pulumiPackages` scope. It uses `lib.makeScopeWithSplicing'`
combined with `lib.packagesFromDirectoryRecursive` over both
`pkgs/plugins` and `pkgs/languages` — the same nixpkgs `lib` functions
nixpkgs' own `pulumiPackages` scope is built from — so every
`pkgs/plugins/<name>/package.nix` (resource providers, §4) and
`pkgs/languages/pulumi-<lang>/package.nix` (language runtimes, §4a) file is
automatically picked up as `pulumiPackages.<name>` without being listed
anywhere else. The two directories are kept separate because they're
different package conventions (§4 vs §4a) merged into one flat scope, not
because the scope itself distinguishes them. The scope's `extra`
attributes make four builders available to every package in the scope via
`callPackage`:

- `mkPulumiPackage` and `mkTerraformBridgeProvider` — both from the
  `pulumi2nix` flake input's `lib` (see below), instantiated once against
  this scope and `nixpkgsPath`.
- `testResourceSchema` and `pulumiTestHook` — `callPackage`d directly from
  nixpkgs' own
  `${nixpkgs}/pkgs/by-name/pu/pulumi/extra/test-resource-schema.nix` and
  `${nixpkgs}/pkgs/by-name/pu/pulumi/extra/pulumi-test-hook.sh` (where
  `nixpkgs` is this flake's `nixpkgs` input path). Their behavior — asserting
  a built provider's `pulumi package get-schema` output matches its pinned
  version, and setting up a throwaway local Pulumi login/stack for
  `checkPhase` — is exactly what nixpkgs already provides, so nothing about
  them is reimplemented or copied here.

### `mkPulumiPackage` and `mkTerraformBridgeProvider`

Both come from `pulumi2nix.lib`, not from a file in this repository.
Underneath, both wrap nixpkgs' own
`${nixpkgs}/pkgs/by-name/pu/pulumi/extra/mk-pulumi-package.nix`, which
already does everything needed for a provider's plugin binary: fetch the
provider's source with `fetchFromGitHub`, build the schema generator
(`cmdGen`) with `buildGoModule`, run it to produce the provider schema, then
build the resource provider binary (`cmdRes`). `pulumi2nix` splits this into
two builders because the schema-generation *invocation* differs by provider
shape:

- `mkPulumiPackage` — for native providers, whose gen tool takes an explicit
  output path and version flag (`<cmdGen> schema.json --version <version>`).
- `mkTerraformBridgeProvider` — for Terraform-bridged providers, whose tfgen
  tool instead takes a `schema` subcommand (`<cmdGen> schema --out .`).

Using the wrong one doesn't fail the build, but produces a broken
`passthru.schema` (each builder hardcodes its own schema-command
convention), so `pkgs/plugins/<name>/package.nix` picks the one that matches
the provider's actual `cmdGen` tool.

```nix
mkPulumiPackage rec {          # or mkTerraformBridgeProvider, for a tfgen-based provider
  owner = "pulumi";
  repo = "pulumi-<name>";
  version = "<version>";
  rev = "v${version}";
  hash = "sha256-...";        # fetchFromGitHub source hash
  vendorHash = "sha256-...";  # Go module vendor hash
  cmdGen = "pulumi-gen-<name>";
  cmdRes = "pulumi-resource-<name>";
  extraLdflags = [ "-X github.com/pulumi/${repo}/provider/pkg/version.Version=v${version}" ];
  meta = { /* description, homepage, license, mainProgram, ... */ };
}
```

`owner`, `repo`, `version`, `rev`, `hash`, and `vendorHash` are the fields
the update automation (§5) rewrites; every other field is static
per-package configuration.

Nixpkgs' upstream builder only exposes `passthru.sdks.python` (via an
optional `pythonArgs` argument), with no equivalent for other SDK
languages. `pulumi2nix` fills that gap: for any `<lang>Args` argument beyond
`pythonArgs` (currently `nodejsArgs`, `goArgs`, `dotnetArgs`), it adds a
matching `passthru.sdks.<lang>` built by its own per-language SDK builder
(`pulumi2nix`'s `lib/sdks/`), mirroring the structure of upstream's
`mkPythonPackage` (source subdirectory, version substitution, propagated
build inputs, import check). Where a package only needs `pythonArgs`, this
layering adds nothing beyond what calling the upstream builder directly
would. Go and .NET SDK layering (`goArgs`, `dotnetArgs`) is available but
not yet exercised by any package in this repo (see `docs/roadmap.md`).

### `pkgs/plugins/<name>/package.nix`

One file per provider. Each calls `mkPulumiPackage` or
`mkTerraformBridgeProvider` (whichever matches the provider's gen-tool
convention, see above) with that provider's static configuration. The
directory name `<name>` is the attribute name the provider is exposed under
(`pulumiPackages.<name>`) and matches the registry package's `name` field
(§3).

### `data/supported-packages.json`

The allowlist that governs which registry packages are built. Keyed by
package name, each entry carries the static configuration the builder needs
that the registry doesn't provide:

```json
{
  "<name>": {
    "repo_url": "https://github.com/pulumi/pulumi-<name>",
    "cmdGen": "pulumi-gen-<name>",
    "cmdRes": "pulumi-resource-<name>"
  }
}
```

A package name present in this file is expected to have a corresponding
`pkgs/plugins/<name>/package.nix`. A package name absent from this
file is not built, regardless of what the registry reports.

### `.github/workflows/ci.yml`

Runs on every pull request. Builds every package under `pulumiPackages`
whose `package.nix` changed in the PR (falling back to building the whole
set for changes outside `pkgs/plugins`), via `nix build`. A pull
request is mergeable once every build it touches succeeds.

### `.github/workflows/update.yml`

Runs on a schedule (§5, §6). Invokes `scripts/update.sh` with credentials
scoped to open pull requests against this repository.

### `scripts/update.sh`

Orchestrates the update flow described in §5.

## 3. Package discovery

The Pulumi registry publishes one metadata file per package under
`pulumi/registry`'s `themes/default/data/registry/packages/<name>.yaml`,
containing at minimum:

```yaml
name: <name>
repo_url: https://github.com/pulumi/pulumi-<name>
version: v<version>
package_status: ga
```

The update automation fetches this metadata for every name present in
`data/supported-packages.json`, reads `version`, and compares it against
the `version` currently pinned in the corresponding
`pkgs/plugins/<name>/package.nix`. Registry packages not present in
`data/supported-packages.json` are not queried and do not affect the
package set.

## 4. Package definition convention

Every `pkgs/plugins/<name>/package.nix` is a `callPackage`-compatible
file whose only non-standard dependency is `mkPulumiPackage` or
`mkTerraformBridgeProvider` (both from `pulumi2nix.lib`, injected by the
scope, §2 — see there for which one a given provider's `cmdGen` convention
calls for). Its required attributes are the same ones nixpkgs' upstream
builder takes:

| Attribute | Meaning |
|---|---|
| `owner`, `repo` | GitHub coordinates of the provider's source repository |
| `version` | The provider's released version, without the leading `v` |
| `rev` | The git ref to fetch, conventionally `"v${version}"` |
| `hash` | `fetchFromGitHub` output hash of the source tree at `rev` |
| `vendorHash` | Hash of the Go module vendor directory for that source tree |
| `cmdGen` | The schema-generator binary's Go command name |
| `cmdRes` | The resource-provider binary's Go command name; becomes the package's `mainProgram` |
| `meta` | Standard nixpkgs `meta` (`description`, `homepage`, `license`, ...) |

Optional attributes:

| Attribute | Meaning |
|---|---|
| `extraLdflags` | Additional `-ldflags` passed to both Go builds, typically to stamp the version into the binary |
| `postConfigure` | Provider-specific schema-generation invocation, when it deviates from the default `cmdGen` call |
| `fetchSubmodules` | Passed through to `fetchFromGitHub` |
| `pythonArgs`, `<lang>Args` | Per-language SDK configuration; presence triggers building the corresponding `passthru.sdks.<lang>` |

A provider whose source layout doesn't fit `buildGoModule` (no `provider/`
subdirectory with `cmd/<cmdGen>` and `cmd/<cmdRes>` packages) does not use
`mkPulumiPackage` or `mkTerraformBridgeProvider`; its `package.nix` instead
calls whatever builder fits its actual layout (`pulumi2nix.lib` also has
`mkComponentPackage`/`mkComponentSchema` for source-based, multi-language
component providers, not yet used by anything in this repo), while still
exposing the same `mainProgram` and `meta` conventions so it's
indistinguishable from the outside.

## 4a. Language runtime packages

Alongside resource providers, `pkgs/languages/pulumi-<lang>/package.nix`
files expose Pulumi *language runtimes* — the `pulumi-language-<lang>`
binaries the `pulumi` CLI shells out to when running a program written in
that language — as `pulumiPackages.pulumi-<lang>`. This is a second,
distinct package convention from §4; neither `mkPulumiPackage`,
`mkTerraformBridgeProvider`, nor
`data/supported-packages.json`/`scripts/update.sh` apply to it.

Two shapes exist, chosen per language:

- **Re-exports** (`go`, `nodejs`, `python`, `bun`): nixpkgs' own
  `pkgs/by-name/pu/pulumi/plugins/pulumi-<lang>/package.nix` already builds
  these from the `pulumi` CLI package's own pinned `src`/`version`. Rather
  than duplicate that logic, this repo's `package.nix` for these languages
  just `callPackage`s the nixpkgs file directly by path, the same pattern
  already used for `testResourceSchema`/`pulumiTestHook` (§2):

  ```nix
  { callPackage, nixpkgsPath }:
  callPackage "${nixpkgsPath}/pkgs/by-name/pu/pulumi/plugins/pulumi-<lang>/package.nix" { }
  ```

  No local `hash`/`vendorHash` pins; version bumps happen automatically
  whenever the `nixpkgs` flake input updates. `pulumi-bun`'s upstream file
  additionally takes a `pulumi-nodejs` argument, resolved via
  `self.callPackage` against this repo's own `pulumiPackages` scope (so
  `pkgs/languages/pulumi-nodejs/package.nix` must exist alongside it).

- **Bespoke builds** (`dotnet`, `java`, `yaml`): no nixpkgs precedent exists
  for these. Each language's host lives in its own upstream repository
  (`pulumi/pulumi-dotnet`, `pulumi/pulumi-java`, `pulumi/pulumi-yaml`) as a
  plain Go module, so `package.nix` calls `buildGoModule` directly against
  a `fetchFromGitHub` source, with its own pinned `hash` and `vendorHash`,
  modeled on nixpkgs' own `pulumi-go`/`pulumi-scala` shape rather than on
  `mkPulumiPackage`. Each disables `doCheck`: their upstream test suites
  need tooling unavailable in the Nix build sandbox (the `dotnet` CLI, a
  sibling `pulumi/pulumi` checkout, or outbound network access), not
  something specific to being packaged here.

Language runtime packages are **not** governed by
`data/supported-packages.json`: that allowlist, and the registry-diffing
half of `scripts/update.sh` (§5), are scoped to resource providers, keyed on
the `cmdGen`/`cmdRes` schema-generation pair that language runtimes don't
have. The bespoke-build subset (`pulumi-dotnet`, `pulumi-java`,
`pulumi-yaml`) does get version-bump automation, from `scripts/update.sh`'s
second, independent loop (§5a) — sourced from GitHub releases rather than
the Pulumi registry. The `pulumi-go`/`pulumi-nodejs`/`pulumi-python`/
`pulumi-bun` re-exports need no such automation: they track whatever
version nixpkgs' own `pulumi` package pins.

## 5. Update automation

`scripts/update.sh`, invoked by the scheduled workflow, performs the
following for every package name in `data/supported-packages.json`:

1. Fetch that package's registry metadata (§3) and read its `version`.
1. Read the `version` currently pinned in
   `pkgs/plugins/<name>/package.nix`.
1. If the two match, do nothing for this package.
1. If the registry version is newer, run:
   ```
   nix-update pulumiPackages.<name> --version=<registry-version>
   ```
   `nix-update` rewrites `version`, `hash`, and `vendorHash` in place in
   `package.nix`, using the package's own `fetchFromGitHub`/`buildGoModule`
   structure to compute the new hashes.
1. Build the updated package: `nix build .#pulumiPackages.<name>`.
1. If the build succeeds: commit the changed `package.nix` on a new branch
   named for the package and its new version, and open a pull request
   against the default branch via `gh pr create`, titled to identify the
   package and version bump.
1. If the build fails: discard the change, and record the package and
   failure in the workflow run's output.

Each package is handled independently: one package's update failure does
not affect any other package's update in the same run, and each successful
update produces its own, separate pull request.

## 5a. Language runtime update automation

`scripts/update.sh` also runs a second, independent loop over every
`pkgs/languages/pulumi-<lang>/package.nix`, after the provider loop above.
For each one:

1. Try to read a pinned `version` string from `package.nix`. If there
   isn't one, the language is a re-export (§4a) with nothing to bump;
   skip it.
1. Otherwise, fetch the latest release of `pulumi/pulumi-<lang>` from the
   GitHub releases API (`gh api repos/pulumi/pulumi-<lang>/releases/latest`)
   and read its `tag_name`, stripping the leading `v`.
1. If the two versions match, do nothing for this package.
1. If the latest release is newer, run the same `nix-update` /
   `nix build` / branch-commit-push / `gh pr create` sequence used for
   providers (§5), just sourced from the GitHub release instead of the
   registry.
1. Build or PR failure discards the change and records it in the run's
   output, exactly as in §5.

No allowlist governs this loop: it's driven directly by which
`pkgs/languages/pulumi-*` directories exist and which of those have a
local version pin, so no separate list needs to be kept in sync with
`pkgs/languages/`.

## 6. CI and validation

A pull request against this repository — whether opened by the update
automation or by a person — is required to pass `.github/workflows/ci.yml`
before merge. That workflow's sole gate is that every affected package
builds successfully with `nix build`. Passing this gate is both necessary
and sufficient for merge from CI's perspective; the merge decision itself
is made by a person reviewing the diff.

## 7. Freshness target

The scheduled workflow (`update.yml`) runs on a cron interval short enough
that, combined with typical review latency for a single-file version bump,
a package's pinned version is expected to converge to the registry's
published version within 24 hours of that version's publication. The
interval is a property of `update.yml`'s `on.schedule` configuration and is
tuned to hold this bound; it is not encoded anywhere else in the system.
