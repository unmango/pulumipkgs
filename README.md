# pulumipkgs

[![Built with Nix](https://img.shields.io/static/v1?label=Built%20with&message=Nix&color=5277C3&logo=nixos&logoColor=white&style=flat-square)](https://builtwithnix.org)
[![CI](https://img.shields.io/github/actions/workflow/status/unmango/pulumipkgs/ci.yml?branch=main&label=ci&style=flat-square)](https://github.com/unmango/pulumipkgs/actions/workflows/ci.yml)
[![Update](https://img.shields.io/github/actions/workflow/status/unmango/pulumipkgs/update.yml?branch=main&label=update&style=flat-square)](https://github.com/unmango/pulumipkgs/actions/workflows/update.yml)
[![Last commit](https://img.shields.io/github/last-commit/unmango/pulumipkgs?style=flat-square)](https://github.com/unmango/pulumipkgs/commits/main)
[![Cachix](https://img.shields.io/badge/cachix-unmango-5277C3?style=flat-square&logo=nixos&logoColor=white)](https://unmango.cachix.org)
[![License](https://img.shields.io/github/license/unmango/pulumipkgs?style=flat-square)](./LICENSE)

A Nix flake exposing `pulumiPackages`: Pulumi resource providers, language runtimes, and source-based (component) plugins.

It mirrors the shape of nixpkgs' own `pulumiPackages` scope, so `pkgs.pulumiPackages.<name>` means the same thing here as it does there.
Where nixpkgs stops at a handful of packages, this set expands toward the [Pulumi registry](https://www.pulumi.com/registry/), and an automated workflow keeps every pin current within a 24 hour window.

## Usage

### Try it without installing anything

```bash
nix build github:unmango/pulumipkgs#pulumi-dotnet
nix shell github:unmango/pulumipkgs#github nixpkgs#pulumi -c pulumi up
```

The Pulumi CLI discovers `pulumi-resource-<name>` and `pulumi-language-<lang>` on `PATH`, so a `nix shell` is enough to run a program against a provider from this set.
Every package is exposed flat under `packages.<system>.<name>`, using the same attribute names as the tables below.

### As a flake input, via the overlay

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    pulumipkgs.url = "github:unmango/pulumipkgs";
  };

  outputs = { nixpkgs, pulumipkgs, ... }:
    let
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [ pulumipkgs.overlays.default ];
      };
    in
    {
      # pkgs.pulumiPackages.github, pkgs.pulumiPackages.pulumi-dotnet, ...
      devShells.x86_64-linux.default = pkgs.mkShell {
        packages = [
          pkgs.pulumi
          pkgs.pulumiPackages.github
          pkgs.pulumiPackages.pulumi-nodejs
        ];
      };
    };
}
```

The overlay adds `pulumiPackages` to your own nixpkgs instantiation, alongside every other package.

### Without the overlay

```nix
pulumipkgs.legacyPackages.${system}.pulumiPackages.github
```

`legacyPackages.<system>` is a full nixpkgs extended with the overlay, so `pulumiPackages` is reachable from it directly.

### Generated SDKs

Providers that configure a language expose their generated SDK bindings under `passthru.sdks.<lang>`:

```bash
nix build github:unmango/pulumipkgs#github.sdks.python
nix build github:unmango/pulumipkgs#github.sdks.nodejs
```

Python is the language every provider is expected to support; others are added per package as they come up.

### Everything at once

```bash
nix profile install github:unmango/pulumipkgs
```

`packages.default` is a `symlinkJoin` of the whole set.
`pulumi-gestalt` is left out of it because it installs the same `bin/pulumi-language-rust` as `pulumi-rust`, and only one can win on `PATH`.
It is still built by CI and still installable on its own.

## Binary cache

CI pushes every build to [`unmango.cachix.org`](https://unmango.cachix.org).
Adding it as a substituter avoids rebuilding providers locally, which is otherwise a long Go build per package.

```nix
{
  nix.settings = {
    substituters = [
      "https://unmango.cachix.org"
      "https://unstoppablemango.cachix.org"
    ];
    trusted-public-keys = [
      "unmango.cachix.org-1:Psb+0nALJfIcYiZLc9JYri4FJGNnzM6goZX7iLErXCI="
      "unstoppablemango.cachix.org-1:m7uEI6X1Ov8DyFWJQX4WsRFRWFuzRW5c/Xms8ZaP74U="
    ];
  };
}
```

Or per invocation, without changing your configuration:

```bash
nix build github:unmango/pulumipkgs#github \
  --substituters https://unmango.cachix.org \
  --trusted-public-keys unmango.cachix.org-1:Psb+0nALJfIcYiZLc9JYri4FJGNnzM6goZX7iLErXCI=
```

## Packages

### Resource providers

Provider plugins, the `pulumi-resource-<name>` binaries the Pulumi CLI runs.
Versions track the Pulumi registry.

| Package | Version | Upstream |
| -------------------- | ------- | -------------------------------------------------------------------------------------- |
| `azuread` | 6.10.0 | [pulumi/pulumi-azuread](https://github.com/pulumi/pulumi-azuread) |
| `command` | 0.9.0 | [pulumi/pulumi-command](https://github.com/pulumi/pulumi-command) |
| `github` | 6.15.0 | [pulumi/pulumi-github](https://github.com/pulumi/pulumi-github) |
| `gitlab` | 10.1.1 | [pulumi/pulumi-gitlab](https://github.com/pulumi/pulumi-gitlab) |
| `random` | 4.14.0 | [pulumi/pulumi-random](https://github.com/pulumi/pulumi-random) |
| `terraform-provider` | 1.1.3 | [pulumi/pulumi-terraform-provider](https://github.com/pulumi/pulumi-terraform-provider) |
| `tls` | 5.5.1 | [pulumi/pulumi-tls](https://github.com/pulumi/pulumi-tls) |

`terraform-provider` builds from a hand-picked [pulumi/pulumi-terraform-bridge](https://github.com/pulumi/pulumi-terraform-bridge) commit rather than a tag on its own repository, so its bumps are reported by the automation but applied by hand.

### Language runtimes

The `pulumi-language-<lang>` hosts the Pulumi CLI shells out to when running a program written in that language.

| Package | Version | Upstream |
| ---------------- | ------------------- | -------------------------------------------------------------------------- |
| `pulumi-bun` | tracks nixpkgs | nixpkgs' own `pulumi` pin |
| `pulumi-dotnet` | 3.112.1 | [pulumi/pulumi-dotnet](https://github.com/pulumi/pulumi-dotnet) |
| `pulumi-gestalt` | 0.0.12 | [andrzejressel/pulumi-gestalt](https://github.com/andrzejressel/pulumi-gestalt) |
| `pulumi-go` | tracks nixpkgs | nixpkgs' own `pulumi` pin |
| `pulumi-java` | 1.36.1 | [pulumi/pulumi-java](https://github.com/pulumi/pulumi-java) |
| `pulumi-nodejs` | tracks nixpkgs | nixpkgs' own `pulumi` pin |
| `pulumi-python` | tracks nixpkgs | nixpkgs' own `pulumi` pin |
| `pulumi-rust` | unstable-2026-08-14 | [pulumi-labs/pulumi-rust](https://github.com/pulumi-labs/pulumi-rust) |
| `pulumi-yaml` | 1.38.4 | [pulumi/pulumi-yaml](https://github.com/pulumi/pulumi-yaml) |

"Tracks nixpkgs" means the package is a thin re-export of nixpkgs' own file for that runtime, with no version pinned here.
It moves whenever this flake's `nixpkgs` input does.

Two of these are community implementations, repackaged here and not authored by this repository.
[`pulumi-labs/pulumi-rust`](https://github.com/pulumi-labs/pulumi-rust) is Apache-2.0, self-described as experimental, and not an official Pulumi project; it has cut no tags, so it is pinned by commit.
Andrzej Ressel's [`pulumi-gestalt`](https://github.com/andrzejressel/pulumi-gestalt) is MPL-2.0 and was archived in August 2026.
Each ships its upstream license text at `$out/share/doc/<pname>/LICENSE`.

### Components

[Source-based plugins](https://www.pulumi.com/docs/iac/guides/building-extending/packages/source-based-plugin/): a source tree that `pulumi package add <path>` reads directly, with no compiled binary.

| Package | Version | Upstream |
| ------------------- | ------------------- | ---------------------------------------------------------------------------------- |
| `pulumi-components` | unstable-2026-08-19 | [UnstoppableMango/pulumi-components](https://github.com/UnstoppableMango/pulumi-components) |

## How it stays current

[`scripts/update.sh`](./scripts/update.sh) runs every 6 hours from [`update.yml`](./.github/workflows/update.yml), comfortably inside the 24 hour freshness target.
It has two independent loops: resource providers are diffed against the Pulumi registry, and locally pinned language runtimes are diffed against their GitHub releases.
Anything behind is bumped with `nix-update`, built, and opened as its own pull request.

Nothing merges itself.
Packages whose `rev` is not derivable from their `version` are marked `"autoUpdate": false` in [`data/supported-packages.json`](./data/supported-packages.json); the run reports their drift but opens no pull request.
See [`docs/roadmap.md`](./docs/roadmap.md) for what is deliberately deferred.

## Development

```bash
nix develop                  # devshell: gh, jq, nix-update, nixfmt
nix build .#                 # build the joined `default` environment
nix build .#github -L        # build one package
nix flake check -L           # build every package and every test
nix fmt                      # nixfmt, mdformat, shellcheck, actionlint
```

`make build`, `make check`, `make fmt`, and `make update` are aliases for the above.

Adding a package means adding one file.
`pkgs/plugins/<name>/package.nix`, `pkgs/languages/pulumi-<lang>/package.nix`, and `pkgs/components/<name>/package.nix` are picked up automatically by `packagesFromDirectoryRecursive`; no list anywhere else needs editing.
Read the matching section of [`docs/spec.md`](./docs/spec.md) first, since the three directories are three different package conventions sharing one flat scope.

There is no unit test framework.
Tests are Nix derivations in a package's `passthru.tests`, surfaced as flake checks named `pulumiPackages-<package>-<test>`, and only written where building the package would not prove the thing that matters.

## Documentation

- [`docs/spec.md`](./docs/spec.md): the design, meant to be stable.
- [`docs/roadmap.md`](./docs/roadmap.md): non-goals, deferred work, open follow-ups.
- [`AGENTS.md`](./AGENTS.md): orientation for AI agents working in this repository.

The `mkPulumiPackage` and `mkTerraformBridgeProvider` builders come from [UnstoppableMango/pulumi2nix](https://github.com/UnstoppableMango/pulumi2nix).
Nothing here reimplements what nixpkgs or `pulumi2nix` already provides.

## License

MIT, see [`LICENSE`](./LICENSE).
