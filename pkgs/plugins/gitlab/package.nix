{
  lib,
  runCommand,
  fetchFromGitHub,
  mkTerraformBridgeProvider,
}:
let
  repo = "pulumi-gitlab";
  version = "10.1.1";
  rev = "v${version}";
  cmdGen = "pulumi-tfgen-gitlab";

  # provider/resources.go imports a `shim` package that upstream's own build
  # generates by patching the `upstream/` submodule at build time (see
  # pulumi-gitlab's `Makefile` `.make/upstream` target and
  # `scripts/upstream.sh`), rather than committing it to the submodule. The
  # gen tool, schema, and plugin derivations all build from `src`, so patch
  # the fetched source once and hand the result to all of them.
  patch = ./patches/0001-expose-provider.patch;

  fetched = fetchFromGitHub {
    name = "source-${repo}-${rev}";
    owner = "pulumi";
    inherit repo rev;
    hash = "sha256-vPi0U8K9ghMADAgwg9ncUv/qOekxRFhYx1Z+zaesv7w=";
    fetchSubmodules = true;
  };

  patchedSrc = runCommand "source-${repo}-${rev}-patched" { } ''
    cp -r ${fetched} source
    chmod -R u+w source
    patch -d source/upstream -p1 < ${patch}
    mkdir -p $out
    cp -r source/. $out/
  '';
in
mkTerraformBridgeProvider {
  inherit repo version cmdGen;
  src = patchedSrc;
  vendorHash = "sha256-eEYzS0bSaXPqz4qf1uPiwS1yvywprlDUaoYCZetaqMg=";
  cmdRes = "pulumi-resource-gitlab";
  extraLdflags = [
    "-X github.com/pulumi/${repo}/provider/v10/pkg/version.Version=v${version}"
  ];
  # Same as the default schemaCommand, except schema generation here also
  # tries to bulk-convert doc examples from HCL by shelling out to the
  # `pulumi` CLI, which in turn needs to download a converter plugin from
  # GitHub releases, network access the Nix sandbox doesn't allow for a
  # non-fixed-output derivation. `--skip-examples` opts out of that step
  # (doesn't affect generated resources/functions, only translated doc
  # examples). Same issue as pulumi-github.
  schemaCommand = "${cmdGen} schema --out . --skip-examples";
  meta = {
    description = "Pulumi provider to manage resources on GitLab";
    mainProgram = "pulumi-resource-gitlab";
    homepage = "https://github.com/pulumi/pulumi-gitlab";
    license = lib.licenses.asl20;
  };
}
