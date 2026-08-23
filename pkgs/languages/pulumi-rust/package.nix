# Packages the language host from pulumi-labs/pulumi-rust, a community Rust
# implementation by the Pulumi Labs contributors. Upstream is Apache-2.0 and
# describes itself as experimental and not an official Pulumi project. Nothing
# here is authored by this repository beyond the Nix expression; the binary and
# the `pulumi new` template are upstream's work, shipped with their LICENSE.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule (finalAttrs: {
  pname = "pulumi-rust";
  # Upstream has no tags or releases yet, so the source is pinned by commit
  # following the same convention as pkgs/components (docs/spec.md §4b).
  version = "unstable-2026-08-14";
  src = fetchFromGitHub {
    owner = "pulumi-labs";
    repo = "pulumi-rust";
    rev = "d62e9f213321befce6f870971e191c9f3946b967";
    hash = "sha256-JSH59tP8N6kze93p3KI5zujAT74y5EBsJXOAgEQ9AQc=";
  };
  sourceRoot = "${finalAttrs.src.name}/pulumi-language-rust";
  vendorHash = "sha256-avSAJgrRODtW5OJ4L8reheyOvfTkpLJs2CIiPzXmUSg=";

  # The conformance suite drives a real `pulumi` CLI and builds the Rust SDK
  # with cargo, neither of which is available in the Nix build sandbox.
  doCheck = false;
  ldflags = [
    "-s"
    "-w"
    # The Nix `version` is an unstable-<date> pin, not something the Pulumi
    # CLI could compare, so stamp upstream Makefile's FALLBACK_DEV_VERSION
    # instead. The symbol path has to match pulumi-language-rust/go.mod
    # exactly; the linker silently drops a -X it cannot resolve.
    "-X=github.com/pulumi-labs/pulumi-rust/pulumi-language-rust/version.Version=0.0.0-dev.0"
  ];

  # `pulumi new` reads the template from a directory rather than from the
  # language host, so it ships alongside the binary instead of inside it.
  # Its Cargo.toml depends on the `pulumi` crate by relative path
  # (../pulumi-rust/sdk/rust/pulumi); the crate is unpublished, so the
  # installed template is a starting point, not something that builds as-is.
  postInstall = ''
    mkdir -p "$out/share/${finalAttrs.pname}"
    cp -r ../templates "$out/share/${finalAttrs.pname}/templates"

    # Ship upstream's license text with the binary built from their source.
    install -Dm644 ../LICENSE "$out/share/doc/${finalAttrs.pname}/LICENSE"
  '';

  meta = {
    homepage = "https://github.com/pulumi-labs/pulumi-rust";
    description = "Community language host for Pulumi programs written in Rust (experimental)";
    license = lib.licenses.asl20;
    mainProgram = "pulumi-language-rust";
  };
})
