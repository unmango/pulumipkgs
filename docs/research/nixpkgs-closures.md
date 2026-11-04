# How nixpkgs keeps Go and Pulumi closures small

Research for #106 (map: #103).
Question: what does nixpkgs already do to keep Go binaries' and Pulumi packages' runtime closures small, and what of it does this flake inherit for free?

All source citations are to nixpkgs at `6774f7bc253789b113a4f39285dc0fa100abeacc`, the `nixpkgs` input pinned in this repo's `flake.lock` (abbreviated `np:` below).
Measurements are `nix path-info -sSh` / `-rsh` on x86_64-linux outputs substituted from `cache.nixos.org`, evaluated with `nix eval -f <nixpkgs> --arg config '{}' --arg overlays '[]'`.
Go is `go_1_26` (1.26.7) at this revision (`np:pkgs/top-level/all-packages.nix:6788`).

## Summary

- `buildGoModule` does three things for closure size by default: `-trimpath` (unless `allowGoReference`), `-buildid=`, and `disallowedReferences = [ go ]`, which makes a stray toolchain reference a build failure rather than a silent 200+ MiB closure.
  It does not strip (`-s -w` is per-package), does not run `remove-references-to`, and does not disable cgo.
- `CGO_ENABLED` defaults to `1` (inherited from the `go` derivation), so every nixpkgs Go binary is dynamically linked against glibc unless the package opts out.
- nixpkgs patches Go's stdlib to hard-code `tzdata`, `iana-etc` and `mailcap` store paths, so every Go binary built with nixpkgs' `go` carries those three paths (about 2.7 MiB) in its closure, static or not.
- Measured "Go floor": 38.7 MiB of runtime closure on top of the binary itself for a cgo-enabled build (glibc + libidn2 + libunistring + libgcc + the three data packages), 2.7 MiB for a `CGO_ENABLED=0` build.
- nixpkgs' Pulumi packages all pass `-s -w`, none set `CGO_ENABLED = 0`, `pulumi` ships a 77 MiB `pulumi-test-language` binary in `out`, and `pulumi-python` drags in all of Python (209 MiB closure) through one patched shebang.
- There is no closure-size regression tooling in nixpkgs itself: no tester, no CI check.
  The only enforcement primitives are Nix's reference checks (`disallowedReferences`/`disallowedRequisites`, and `outputChecks` with `__structuredAttrs`).
- pulumipkgs' re-exported hosts (`pulumi-{go,nodejs,python,bun}`) `callPackage` these exact files, so they inherit every default above, good and bad, with no local lever except overriding.

## 1. `buildGoModule` defaults

Source: `np:pkgs/build-support/go/module.nix`, documented in `np:doc/languages-frameworks/go.section.md`.

| Behaviour | Where | Effect on closure |
| --- | --- | --- |
| `allowGoReference ? false` | `module.nix:53` | Gates the next two rows. Manual: "shouldn't be set without a good reason" (`go.section.md:184-188`). |
| `GOFLAGS += -trimpath` when `!allowGoReference` | `module.nix:234-236` | Strips `$GOROOT`/build paths from the binary, which is what normally removes the `go` store path from it. Tests drop it again (`module.nix:376-377`), but tests don't produce outputs. |
| `disallowedReferences = lib.optional (!allowGoReference) go` | `module.nix:400` | Nix fails the build if `$out` still references the toolchain. A guard, not a shrinker. |
| `ldflags += -buildid=` unless one is given | `module.nix:243` | Reproducibility, not size. |
| `CGO_ENABLED = args.env.CGO_ENABLED or go.CGO_ENABLED` | `module.nix:225` | Defaults to the compiler's value, which is `1` on every mainstream platform (`np:pkgs/development/compilers/go/1.26.nix:81-90`; manual `go.section.md:256-279`: "`env.CGO_ENABLED` defaults to `1`"). |
| `strictDeps = true` | `module.nix:397` | Keeps native build tools out of host references. |
| Install copies `$GOPATH/bin` only | `module.nix:392` | `out` holds only binaries; no sources or `pkg/` cache. |
| Builds every `main` package under `modRoot` when `subPackages` is unset | `module.nix:322-333` (`getGoDirs`) | Can install binaries nobody asked for; see `pulumi` below. |

What `buildGoModule` does **not** do:

- No `-s -w`. Each package adds it to `ldflags` itself. The ordinary `stdenv` strip phase still runs (all outputs below report `stripped`).
- No `remove-references-to`. It is a generic stdenv tool (`np:doc/stdenv/stdenv.chapter.md:1210-1220`), not wired into the Go builder; nothing under `np:pkgs/by-name/pu/pulumi/` uses it either.
- No static default. The manual describes `env.CGO_ENABLED = 0` as the opt-out that makes "the resulting binary statically linked" and notes that with cgo on, `net` and `os/user` link C even when the program never calls C (`go.section.md:258-263`).

### The stdlib data-path patches

`np:pkgs/development/compilers/go/1.26.nix:49-62` applies three `replaceVars` patches to Go's own source:

- `tzdata-1.19.patch`: prepends `@tzdata@/share/zoneinfo/` to `time.platformZoneSources`, keeping `/usr/share/zoneinfo/` as a fallback.
- `iana-etc-1.25.patch`: *replaces* `/etc/protocols` and `/etc/services` in `net` with `@iana@/etc/...`; no fallback.
- `mailcap-1.17.patch`: prepends `@mailcap@/etc/mime.types` to `mime.typeFiles`.

Because those are string constants in the stdlib, any binary that links `time`, `net` or `mime` (in practice all of them) keeps a reference.
`-trimpath` and `-s -w` do not touch string data.
`strings` on `pulumi-language-go` finds exactly four store paths: `glibc`, `tzdata`, `iana-etc`, `mailcap`.

### Measured: what cgo costs

| Output | Linking | Closure beyond the binary |
| --- | --- | --- |
| `pulumiPackages.pulumi-go` (cgo default) | dynamic, interpreter `glibc-2.42-84/lib/ld-linux-x86-64.so.2` | glibc 33.4 MiB, libunistring 2.0, libidn2 0.36, xgcc-libgcc 0.19, tzdata 2.0, iana-etc 0.56, mailcap 0.12 = **38.7 MiB** |
| `uplosi` (`env.CGO_ENABLED = "0"`, `np:pkgs/by-name/up/uplosi/package.nix:23`) | statically linked | tzdata, iana-etc, mailcap = **2.7 MiB** |

`uplosi` is the package nixpkgs itself uses as its `CGO_ENABLED=0` reference in the Go compiler tests, which assert the binary is ELF type `EXE` and linked by Go's internal linker (`np:pkgs/development/compilers/go/tests.nix:11-60`).
The 36 MiB glibc floor is shared, so it is paid once per closure, not once per binary; but it is paid by every closure, including a container image holding one plugin.

## 2. nixpkgs' `pulumi` and `pulumiPackages`

### Structure

- `pulumi` is a single-output `buildGoModule` with `sourceRoot = pkg`, `tags = [ "osusergo" ]`, `ldflags = [ "-s" "-w" "-X=...Version=..." ]` (`np:pkgs/by-name/pu/pulumi/package.nix:18-45`).
  `postInstall` generates bash/fish/zsh completions into `share/` (`:188-193`).
- `pulumiPackages = recurseIntoAttrs pulumi.pkgs` (`np:pkgs/top-level/all-packages.nix:2655`), where `pulumi.pkgs = callPackage ./plugins.nix { }` (`package.nix:196`).
  `plugins.nix` is `makeScopeWithSplicing'` + `packagesFromDirectoryRecursive` over `./plugins`, with `extra` injecting `mkPulumiPackage`, `testResourceSchema`, `pulumiTestHook` (`plugins.nix:1-26`): the shape this repo mirrors.
- `mkPulumiPackage` (`np:pkgs/by-name/pu/pulumi/extra/mk-pulumi-package.nix`) builds the gen tool and the provider with the same `mkBasePackage`: `subPackages = [ "cmd/${cmd}" ]`, `doCheck = false`, `ldflags = [ "-s" "-w" ] ++ extraLdflags` (`:19-34`).
  The gen tool is only in the provider's `nativeBuildInputs` (`:163-165`), so it never reaches the runtime closure.
  The Python SDK is a separate derivation under `passthru.sdks.python` (`:180-187`), not an output.
- `pulumi.withPackages f` (`np:pkgs/by-name/pu/pulumi/with-packages.nix`) is a `runCommand` that `makeBinaryWrapper`s `bin/pulumi` with `--suffix PATH` of the chosen plugins' `bin` and symlinks `share` (`:13-31`).
  Its closure is `pulumi` + each plugin + the wrapper's own (glibc) dependency.
- Language hosts (`plugins/pulumi-{go,nodejs,python,bun}/package.nix`) all `inherit (pulumi) version src` and `buildGoModule` one `sourceRoot` each, with `-s -w`.
  `pulumi-bun` is a `symlinkJoin` of `pulumi-bun-unwrapped` and `pulumi-nodejs` (`plugins/pulumi-bun/package.nix:24-35`).

No nixpkgs Pulumi derivation sets `outputs`, `CGO_ENABLED`, `allowGoReference`, `removeReferencesTo` or a size check.

### Measured

| Output | Self | Closure | What is in it |
| --- | --- | --- | --- |
| `pulumi` 3.263.0 | 195.0 MiB | 233.7 MiB | `bin/pulumi` 118 MiB, **`bin/pulumi-test-language` 77 MiB**, `share/` completions 0.8 MiB, Go floor |
| `pulumi-go` | 37.5 | 76.2 | binary + Go floor |
| `pulumi-nodejs` | 33.9 | 83.9 | binary + `pulumi-resource-pulumi-nodejs` shell script → **bash-interactive** (7.1 MiB self, plus ncurses, readline) + Go floor |
| `pulumi-python` | 34.1 | **251.1** | binary + `pulumi-language-python-exec` with `#!.../python3-3.14.7/bin/python` → **python3 135.4 MiB self, 209.4 MiB closure**; `pulumi-resource-pulumi-python` → bash |
| `pulumi-bun` | 1.1 KiB | 85.7 | `pulumi-bun-unwrapped` 1.8 MiB + all of `pulumi-nodejs` |
| `pulumi-command` 0.9.0 | 24.1 | 62.8 | binary + Go floor |
| `pulumi-random` 4.14.0 | 26.5 | 65.2 | binary + Go floor |
| `pulumi-kubernetes` 4.25.0 | 294.7 | 333.4 | one stripped binary + Go floor |

Notes on the outliers:

- `pulumi-test-language` is there because `pulumi` sets `excludedPackages` but no `subPackages`, so `getGoDirs` installs every `main` package under `pkg/` (`package.nix:33,47-50`; `module.nix:322-333`).
  It is 40% of `pulumi`'s `out`.
  (pulumipkgs does not ship the `pulumi` CLI, so this matters only to consumers who pair this flake with nixpkgs' `pulumi`.)
- The script references come from `buildInputs = [ bash ]` / `[ bash python3 ]` (`plugins/pulumi-nodejs/package.nix:39-42`, `plugins/pulumi-python/package.nix:38-42`), whose comment says they exist "For patchShebangsAuto".
  In nixpkgs `bash` *is* the interactive build (`all-packages.nix:3029-3036`: `bashInteractive = bash`, with `bashNonInteractive` separate), which is why the closure shows `bash-interactive`.
  The Python interpreter is arguably a real runtime dependency of the Python host (it runs user programs), but it pins one specific `python3` rather than the user's.
- `pulumi-kubernetes` is large because the provider is large, not because of references; its closure beyond the binary is the same Go floor.

## 3. Closure-size regression tooling

Searched `np:pkgs/build-support/testers/`, `np:ci/`, `np:lib/`, `np:doc/`:

- No tester asserts closure size.
  `testers/` holds `testVersion`, `shellcheck`, `hasPkgConfigModules`, `testEqualDerivation` and similar, nothing size-related.
- nixpkgs CI (`np:ci/eval/`) compares evaluation statistics; its only "closure size" mentions are comments about trimming the CI tooling's own closure.
- `closureInfo` (`np:pkgs/build-support/closure-info.nix`) writes `$out/total-nar-size` for a set of roots; it is the building block a size check would use, but nothing in nixpkgs uses it as a gate.
- The enforcement primitives are Nix's, not nixpkgs': `allowedReferences`/`disallowedReferences`/`allowedRequisites`/`disallowedRequisites`, as `buildGoModule` uses for `go`.
  `np:doc/release-notes/rl-2511.section.md:72` notes these now need `__structuredAttrs = true` when combined with `separateDebugInfo`.
  Nix also offers per-output `outputChecks.<out>.maxSize` / `maxClosureSize` under `__structuredAttrs` (from the Nix manual's derivation attributes, not from nixpkgs source; not verified at a pinned Nix version here).
- Multiple outputs are the manual's stated main tool for "reducing runtime closure sizes" (`np:doc/stdenv/multiple-output.chapter.md:5`), with a warning that `symlinkJoin` over them "may negate some closure size benefits" (`:24`), which is relevant to `packages.default`.

## 4. What pulumipkgs inherits

- `pkgs/languages/pulumi-{go,nodejs,python,bun}/package.nix` are each one line: `callPackage "${nixpkgsPath}/pkgs/by-name/pu/pulumi/plugins/<name>/package.nix" { }`.
  They are evaluated in this flake's scope, but none of their arguments (`buildGoModule`, `pulumi`, `bash`, `python3`, `nodejs`) is defined in that scope except `pulumi-nodejs` for `pulumi-bun`, which is itself the same re-export.
  So the derivations should be identical to nixpkgs' and substitute from `cache.nixos.org`; the measurements above are their closures.
  (Inferred from the expressions; a flake-level `nix eval` comparing out paths was not possible in this session because other flake inputs could not be fetched.)
- Inherited for free: `-trimpath`, `disallowedReferences = [ go ]`, `-s -w` (the hosts set it themselves), `strictDeps`, gen tools staying build-time only.
- Inherited, and costing size: cgo-on dynamic linking (glibc floor, about 36 MiB, shared across the joined env), the tzdata/iana-etc/mailcap references (2.7 MiB, even if static), `bash-interactive` in `pulumi-nodejs`/`pulumi-bun`, and python3 in `pulumi-python`.
  The re-exports have no local pin to change, so any of these needs an `overrideAttrs` here or a change upstream, which is the open "nixpkgs re-exports" question on #103.
- pulumi2nix's builders call the same `buildGoModule`, so they get the same defaults: `mkProviderPlugin` sets `subPackages = [ "cmd/${cmdRes}" ]`, `doCheck = false`, `-s -w` (`pulumi2nix/lib/mk-provider-plugin.nix`, at the locked rev `9e4acfe`), and no `CGO_ENABLED`.
  So every provider plugin in this flake today carries the same 38.7 MiB floor as nixpkgs' `pulumi-command`.

## Implications for #103 (not decisions)

- `CGO_ENABLED = 0` is the single largest lever for a lone-plugin closure (38.7 → 2.7 MiB of floor); in the joined env it is a one-time 36 MiB.
  nixpkgs gives it a documented knob and a test that proves the result is static, so a builder default in pulumi2nix would not be reinventing anything.
- The 2.7 MiB data floor survives static linking.
  Removing it with `remove-references-to` would be safe for `tzdata` and `mailcap` (fallback paths remain) but would break `/etc/protocols`/`/etc/services` lookups, which the iana patch replaces with no fallback.
- An output-size check, if wanted, would have to be written locally on `closureInfo` or Nix `outputChecks`; nixpkgs has none to reuse.

## Confidence

- High: everything cited to a file and line, and the measured sizes (taken directly from substituted outputs at the pinned revision).
- Medium: that pulumipkgs' re-exports produce byte-identical out paths (inferred from the expressions, not evaluated through the flake).
- Medium: the Nix `outputChecks.maxClosureSize` attribute (from the Nix manual, not checked against the pinned Nix).
