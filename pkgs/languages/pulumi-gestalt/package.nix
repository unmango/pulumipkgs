# Packages the Rust language host from Pulumi Gestalt, written by Andrzej
# Ressel (github.com/andrzejressel) and released under the MPL-2.0. Every
# binary and library this file produces is built from their source; the Nix
# expression is the only part authored here, and the one upstream change it
# makes (the go.mod `replace`, below) is a packaging repair, not a fork.
#
# Upstream archived the project in August 2026. It is packaged because it is
# a real, working implementation of Rust support that predates the alternative
# in pkgs/languages/pulumi-rust, and credit for it belongs with its author.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  rustPlatform,
}:
let
  version = "0.0.12";
  src = fetchFromGitHub {
    owner = "andrzejressel";
    repo = "pulumi-gestalt";
    tag = "v${version}";
    hash = "sha256-1jFHgctKNhUEUF3ZsmaKW60ip0jvtrqhmsu6bJoVReM=";
  };

  # The language host's rust2go bindings (pulumi-language-rust/codegen/rust)
  # are cgo, linking a staticlib built from this same tree by
  # `cargo build -p pulumi_gestalt_rust_language_server --release`. Building
  # it as its own derivation keeps the Rust and Go halves independently
  # cached; the Go build below stages the archive where cgo expects it.
  bridge = rustPlatform.buildRustPackage {
    pname = "pulumi-gestalt-rust-language-server";
    inherit version src;
    cargoHash = "sha256-MtZH111h9KwIn7nAUj9bNLHDACrRrM4IZnXE6QaWUhc=";

    # Built from the workspace root rather than with buildAndTestSubdir: the
    # crate reaches its siblings through workspace `path` dependencies, which
    # do not resolve from inside a subdirectory.
    cargoBuildFlags = [
      "-p"
      "pulumi_gestalt_rust_language_server"
    ];

    doCheck = false;

    # Only the staticlib is wanted; the crate produces no binary to install.
    installPhase = ''
      runHook preInstall

      mkdir -p "$out/lib"
      cp target/*/release/libpulumi_gestalt_rust_language_server.a "$out/lib/"

      install -Dm644 LICENSE "$out/share/doc/pulumi-gestalt-rust-language-server/LICENSE"

      runHook postInstall
    '';

    # This derivation is where the project's Rust sources actually land, so it
    # carries its own provenance rather than relying on the Go package below.
    meta = {
      homepage = "https://github.com/andrzejressel/pulumi-gestalt";
      description = "Rust code-generation bridge linked into the Pulumi Gestalt language host";
      license = lib.licenses.mpl20;
    };
  };
in
buildGoModule {
  pname = "pulumi-gestalt";
  inherit version src;

  # modRoot rather than sourceRoot: the repository has no root go.mod, and
  # the archive below has to be staged in the repository root, which the
  # sourceRoot form leaves read-only.
  modRoot = "pulumi-language-rust";
  vendorHash = "sha256-fUzb/op7bibXQBESOgaJXKYL9NX1rzbN49AS5xFqVec=";

  # go.mod replaces github.com/ihciah/rust2go with andrzejressel/rust2go at
  # d0612109, a commit no longer reachable from any ref in the fork (whose
  # master sits at the 6f06b069 the `require` line already names). Go
  # resolves module revisions through refs, so the replacement cannot be
  # fetched at all and no GOPROXY setting recovers it.
  #
  # Dropping the replacement is a no-op for this build: the fork's only delta
  # against 6f06b069 is in rust2go-cli, Rust code that regenerates
  # codegen/rust/api.go, and that file is committed. The Go package this
  # module imports (rust2go/asmcall) is identical either way.
  #
  # That leaves go.sum without an entry for the now-unreplaced module, so the
  # upstream one is added. Its /go.mod hash is byte-identical to the fork
  # entry go.sum already carries, which is the same evidence that the two
  # are the same module.
  postPatch = ''
    substituteInPlace pulumi-language-rust/go.mod \
      --replace-fail \
        "replace github.com/ihciah/rust2go => github.com/andrzejressel/rust2go v0.0.0-20260316163702-d06121090dcd" \
        ""

    {
      echo "github.com/ihciah/rust2go v0.0.0-20260314034108-6f06b0697c1b h1:5t8wONjmMs2KNn8E4LAIu0XeYRjv/k7UJ37NZrI62rU="
      echo "github.com/ihciah/rust2go v0.0.0-20260314034108-6f06b0697c1b/go.mod h1:SpcZZoVYDXYhx373JZ1onR8dnEcalKA0H61x/FJ9O0s="
    } >> pulumi-language-rust/go.sum
  '';

  # codegen/rust/api.go hardcodes the archive's path relative to itself
  # (''${SRCDIR}/../../../target/release), so staging it there is enough and
  # no NIX_LDFLAGS override is needed. postConfigure rather than preBuild:
  # the latter is inherited by the go-modules derivation, which only fetches
  # modules and has no reason to depend on the Rust half.
  postConfigure = ''
    mkdir -p ../target/release
    cp ${bridge}/lib/libpulumi_gestalt_rust_language_server.a ../target/release/
  '';

  # Ship upstream's license text with the binary built from their source.
  postInstall = ''
    install -Dm644 ../LICENSE "$out/share/doc/pulumi-gestalt/LICENSE"
  '';

  # The language tests drive a real `pulumi` CLI and reach the network,
  # neither of which is available in the Nix build sandbox.
  doCheck = false;

  # No ldflags: the host reports a `pluginVersion` const in main.go rather
  # than a linker-stamped symbol.

  meta = {
    homepage = "https://github.com/andrzejressel/pulumi-gestalt";
    description = "Community language host for Pulumi programs written in Rust, from Andrzej Ressel's archived Pulumi Gestalt project";
    license = lib.licenses.mpl20;
    mainProgram = "pulumi-language-rust";
  };
}
