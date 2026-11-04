# Go build settings that shrink Pulumi plugin binaries beyond `-s -w`

Research for #105, part of the #103 wayfinder (size-optimized Pulumi tooling derivations).

## Answer

No Go build flag left on the table buys more than about 1% on a bridged provider, apart from `-gcflags=all=-l`, which costs runtime speed.
The two settings that matter are already in place or cheap: `-trimpath` (nixpkgs adds it) and `CGO_ENABLED=0`.
`CGO_ENABLED=0` is worth adopting for its closure effect, not its byte count: it makes the binary static, so it stops referencing glibc.
The bulk of a bridged provider is code that is linked in because of what it imports, which no flag removes.
That is the runtime plugin importing the bridge's schema generator `pkg/tfgen`, plus reflection that switches off the linker's method dead-code elimination.
Fixing it is a source change upstream, not a builder setting.

## How this was measured

`nix build` could not run in the research sandbox: fetching the pinned nixpkgs from GitHub was refused, so nothing could be evaluated.
Builds ran with the plain Go toolchain instead, using settings that copy what `buildGoModule` passes (listed below).

- Subject: `pulumi-resource-random`, from `github.com/pulumi/pulumi-random/provider/v4@v4.0.0-20261102222436-36cb3839dfe4`.
  That is the proxy's current HEAD, not the `4.21.1` pinned in `pkgs/plugins/random/package.nix`.
  It builds against `pulumi-terraform-bridge/v3 v3.142.0` and `pulumi/sdk/v3 v3.272.0`.
  The module zip leaves out the nested `./shim` module, so a two-line equivalent was written by hand: it calls `internal/provider.New()` from `terraform-provider-random`.
- Toolchain: go1.26.10 linux/amd64, because that module's `go.mod` requires it.
  The pinned nixpkgs (`6774f7bc`) ships `go = go_1_26` at 1.26.7 (`pkgs/top-level/all-packages.nix`, `pkgs/development/compilers/go/1.26.nix`).
- Baseline settings: `-trimpath -ldflags="-s -w -buildid="`, with CGO on, which matches buildGoModule's defaults (next section).
- These are absolute byte counts for one provider at one version.
  Treat the ratios as the result and the exact sizes as an illustration.

| Variant (each one change from the baseline) | Bytes | Change from baseline |
| --- | ---: | ---: |
| No `-s -w` (unstripped) | 108,919,612 | +43.0% |
| No `-s -w`, then `strip -S` (what nixpkgs' fixup strip does) | 89,013,904 | +16.8% |
| **Baseline** (`-trimpath`, `-s -w -buildid=`, CGO on) | **76,194,021** | 0 |
| Without `-trimpath` | 76,697,829 | +0.66% |
| `-buildvcs=false` | 76,194,021 | 0 (identical) |
| `GOAMD64=v3` | 76,177,637 | −0.02% |
| `CGO_ENABLED=0` | 76,066,942 | −0.17% |
| `-tags=grpcnotrace` | 75,895,013 | −0.39% |
| `-tags=nethttpomithttp2` | 75,862,245 | −0.44% |
| `-tags=grpcnotrace,nethttpomithttp2` | 75,559,141 | −0.83% |
| `CGO_ENABLED=0` and both tags | 75,432,062 | −1.00% |
| `-gcflags=all=-l` (no inlining) | 69,443,813 | −8.86% |

## Setting by setting

### `-s -w` (already set)

`-s` omits the symbol table and debug information and implies `-w`, which omits DWARF (`src/cmd/link/doc.go`, go1.26.10).
This matters even under Nix.
nixpkgs' fixup phase strips binaries in `bin` with `strip -S -p` by default (`stripDebugFlags`, `pkgs/build-support/setup-hooks/strip.sh`), and that removes only debug sections.
In the table, `strip -S` brings the unstripped binary down to 89.0 MB, and `-s -w` goes on to 76.2 MB.
`.gopclntab` (28 MB here) is not symbol information that `-s` removes: the Go runtime needs it for stack traces and GC, so it stays.

All pulumi2nix builders pass `-s -w` (`lib/mk-provider-plugin.nix`, `lib/mk-gen-tool.nix`, `lib/mk-dynamic-plugin.nix`), and so do the bespoke language hosts `pulumi-dotnet`, `pulumi-java`, `pulumi-yaml` and `pulumi-rust`.
**`pkgs/languages/pulumi-gestalt` sets no `ldflags` at all** (its comment says there is no version symbol to stamp), so its Go binary gets only nixpkgs' `strip -S`.
Judging by the gap in the table, adding `-s -w` there should save roughly 15% of that binary; gestalt itself was not measured.

### `-trimpath` (already set by `buildGoModule`)

buildGoModule appends `-trimpath` to `GOFLAGS` unless `allowGoReference = true`, and it warns if you add the flag yourself (`pkgs/build-support/go/module.nix` lines 234–236 at the pinned rev).
The same switch sets `disallowedReferences = [ go ]` (line 400), so a stray reference to the Go toolchain fails the build instead of quietly pulling Go into the closure.
No package in this repo or in pulumi2nix sets `allowGoReference`.
The flag replaces absolute file paths with `module@version` paths (`go help build`, `src/cmd/go/alldocs.go`), which saved 0.5 MB here.
Its real job is keeping `/build/...` and store paths out of the binary, and that already happens.

buildGoModule also adds `-buildid=` to `ldflags` by default (module.nix line 243) for reproducibility.
It saves nothing measurable.

### `-buildvcs=false`: no effect

With the default `auto`, Go stamps VCS information only when the main package, its module and the current directory all sit in the same repository (`go help build`).
A Nix build's source is an unpacked tarball with no `.git`, and so was this one, so the output came out byte-identical.
It would matter only for a `fetchgit { leaveDotGit = true; }` source, and the bytes involved are a few hundred.

### `CGO_ENABLED=0`: small in bytes, large in closure

nixpkgs' Go sets `CGO_ENABLED = 1` on every platform except WASI and big-endian POWER64 (`pkgs/development/compilers/go/1.26.nix` lines 80–89).
buildGoModule passes that through unless `env.CGO_ENABLED` is set (module.nix line 225).
With CGO on, the provider is dynamically linked against libc through `net` and `os/user`, and buildGoModule points its ELF interpreter at Nix's glibc through `GO_LDSO`.
So every cgo-default plugin carries glibc in its runtime closure.
With `CGO_ENABLED=0`, `file` reports the binary as `statically linked`, and it is 127 KB smaller.
The glibc closure size was not measured, because there was no nixpkgs evaluation to measure it with.
#103 already allows this trade-off.
One package here already does it: `pkgs/plugins/terraform-provider` sets `env.CGO_ENABLED = 0`.
The cost is the pure-Go DNS resolver and user lookup: no NSS modules, and no `/etc/nsswitch.conf` beyond what the Go resolver parses itself.
That is normal for plugins talking gRPC to localhost and HTTPS to APIs.
`pulumi-gestalt` cannot do this: it links a Rust staticlib through cgo.

### Build tags

- `grpcnotrace`: grpc-go's own comment says it avoids importing `golang.org/x/net/trace`, "which in turn enables binaries using gRPC-Go for dead code elimination, which can yield 10-15% improvements in binary size" (`google.golang.org/grpc@v1.83.2/trace_notrace.go`).
  Here it saved 0.39%.
  The payoff fails to appear because `x/net/trace` hurts by pulling in `html/template`, which turns off method dead-code elimination (next section).
  The bridge and its dependencies import `text/template` anyway (`pkg/tfbridge/examples.go`, `spf13/cobra`, `muesli/termenv`), so that elimination was already lost.
  Cost: gRPC's `/debug/requests` tracing goes away; Pulumi does not use it.
- `nethttpomithttp2`: this tag drops the bundled HTTP/2 implementation from `net/http` (`src/net/http/omithttp2.go`).
  It saved 0.44%.
  It is undocumented in `go help buildconstraint`, it disables HTTP/2 for every `net/http` client and server in the plugin, and a cloud API client that expects h2 can change behaviour.
  Not worth 0.3 MB.
- Tags that drop unused backends: none of the dependencies traced here exposes a tag that drops what is actually large (go-getter's S3/GCS getters, the gRPC xDS client, aws-sdk-go-v2).
  Those come in through imports, not through optional files (next section).

### `GOEXPERIMENT` and other compiler or linker flags

go1.26's experiment list (`src/internal/goexperiment/flags.go`) has nothing aimed at binary size: FieldTrack, PreemptibleLoops, StaticLockRanking, BoringCrypto, Regabi*, HeapMinimum512KiB, Arenas, CgoCheck2, LoopVar, NewInliner, Dwarf5, JSONv2, GreenTeaGC, RandomizedHeapBase64, RuntimeFreegc, SizeSpecializedMalloc, GoroutineLeakProfile, SIMD, RuntimeSecret.
`Dwarf5` changes DWARF, which `-w` already removes.
`GOAMD64=v3` saved 16 KB and stops the binary running on pre-Haswell x86-64; reject it.
`-gcflags=all=-l` turns off inlining and is the only flag with a real effect (−8.9%).
It slows every hot path in the bridge, the gRPC stack and protobuf marshalling.
#103 does not list speed as an acceptable trade-off, so treat this as rejected unless someone decides otherwise.

## Where the bytes go, and why flags cannot reach them

On the unstripped baseline, the file-backed sections are `.text` 33.2 MB, `.gopclntab` 28.2 MB, `.rodata` 12.1 MB and `.noptrdata` 1.9 MB.
The 36 MB `.noptrbss`, mostly `crypto/internal/fips140/drbg.memory`, takes no space in the file.

The largest contributors among the symbols that make it into the file include:

- `github.com/aws/aws-sdk-go-v2` 4.5 MB, `github.com/envoyproxy/go-control-plane` 3.5 MB, `cloud.google.com/go/storage` and `google.golang.org/api/storage` 0.65 MB.
  Together with `hashicorp/go-getter`, the gRPC xDS packages, `go-git`, `pkg/tf2pulumi` and `pkg/tfgen`, they come to **10.9 MB of symbol bytes**, before counting their share of `.gopclntab`.
  A provider that only serves CRUD over gRPC needs none of this.
- The path in the import graph (`go list -deps`) runs from the runtime plugin's `main`:
  `pkg/pf/tfbridge` → `pkg/tfgen` → `pkg/tf2pulumi/convert` → `pkg/tf2pulumi/internal/config/module` → `hashicorp/go-getter` → `aws-sdk-go-v2/service/s3`, and on through `cloud.google.com/go/storage` → `grpc/xds/googledirectpath` → envoy.
  The `pkg/pf/tfbridge` → `pkg/tfgen` edge is `pkg/pf/tfbridge/provider_mux.go`, where `NewMuxProvider` calls `tfgen.GenerateSchema` as a fallback when no prebuilt schema is passed in (bridge v3.142.0).
  `pkg/tfgen` → `pulumi/sdk/v3/go/common/workspace` → `util/securestore` → `zalando/go-keyring` → `godbus/dbus` pulls in a D-Bus client, too.

Two linker behaviours keep that code once it is imported:

1. **Package initialisers always run.**
   Package-level maps and `init` functions, such as go-getter's table of getters, are reachable from `main..inittask` whatever is called at runtime.
   Everything they reference therefore survives dead-code elimination.
2. **Reflection turns off method dead-code elimination.**
   The linker's `deadcode` pass keeps every exported method of every reachable type as soon as one reachable function is marked REFLECTMETHOD.
   A function gets that mark by calling `reflect.Value.Method`/`Type.Method`, or `MethodByName` with an argument that is not a constant (`src/cmd/link/internal/ld/deadcode.go`, the comment above `func deadcode` and lines 452–462).
   The linker's `-dumpdep` output for this binary shows ten REFLECTMETHOD functions:
   - `text/template.(*state).evalField`
   - `github.com/pulumi/pulumi/sdk/v3/go/internal.CallToOutputMethod`
   - `github.com/pulumi/pulumi-terraform-bridge/v3/pkg/pf/internal/pfutils.{callGetter,extractNestedAttributes,extractBlockNesting}`
   - `github.com/godbus/dbus/v5.{getMethods,getAllMethods}`
   - `github.com/google/go-cmp/cmp/internal/value.appendTypeName`
   - two `reflect.Value.Methods` closures

   The SDK's `CallToOutputMethod` and the bridge's `pfutils` are both on the runtime path, so even a provider with no templates or keyring would lose method elimination.
   How much method elimination would save was not measured: the linker has no switch that turns it back on.

The levers that can actually move these bytes belong in later #103 tickets, not in this one:

- Upstream: split `NewMuxProvider`'s on-the-fly `tfgen.GenerateSchema` fallback (or `pkg/tfgen` as a whole) out of the runtime path of `pkg/pf/tfbridge`.
  Bridged providers ship a prebuilt schema (`schema-embed.json`), so the fallback is dead weight for them.
- Upstream: replace the non-constant `MethodByName` calls in `pfutils` and `sdk/go/internal` with interface assertions or constant names.
  That alone does not bring method elimination back while `text/template` is reachable.

## Recommendations for the #103 spec

1. Keep `-s -w` and buildGoModule's default `-trimpath`/`-buildid=`; do not add `-buildvcs=false`, because it does nothing for Nix sources.
2. Add `-s -w` to `pkgs/languages/pulumi-gestalt` (roughly a 15% saving on that binary, by the ratio measured here).
3. Default the pulumi2nix builders to `env.CGO_ENABLED = 0`, with a per-package opt-out for cgo hosts such as gestalt.
   The win is dropping glibc from the closure, not the 0.2% in bytes; measure the closure with `nix path-info -rS` once nixpkgs can be evaluated.
4. Do not adopt `grpcnotrace`, `nethttpomithttp2`, `GOAMD64=v3`, any `GOEXPERIMENT`, or `-gcflags=-l`: together they buy at most 1% (or 9% at a speed cost) and carry behaviour or portability risk.
5. Open an upstream issue against pulumi-terraform-bridge for the `pf/tfbridge` → `tfgen` import edge.
   That is where a bridged provider's double-digit share of dead weight comes from.

## Confidence

- High for the buildGoModule and nixpkgs facts: they were read straight from the pinned rev's source.
- High for the flag ratios on this provider; medium for carrying them over to other providers and versions.
  Sizes came from go1.26.10 outside Nix, not from nixpkgs' go 1.26.7 inside Nix, and from random's HEAD rather than its `4.21.1` pin.
- Medium for the gestalt estimate (inferred, not built) and for the closure benefit of `CGO_ENABLED=0` (follows from how the binary is linked, not measured with `nix path-info`).
