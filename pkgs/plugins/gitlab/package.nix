{
  lib,
  fetchFromGitHub,
  mkTerraformBridgeProvider,
}:
let
  repo = "pulumi-gitlab";
  version = "10.2.0";
  rev = "v${version}";
  cmdGen = "pulumi-tfgen-gitlab";

  # provider/resources.go imports a `shim` package that upstream's own build
  # generates by patching the `upstream/` submodule at build time (see
  # pulumi-gitlab's `Makefile` `.make/upstream` target and
  # `scripts/upstream.sh`), rather than committing it to the submodule. The
  # gen tool, schema, and plugin derivations all build from `src`, so patch
  # the fetched source once and hand the result to all of them.
  #
  # The patch is applied in `postFetch` rather than in a wrapper derivation so
  # that `src` stays a plain fetcher: `nix-update` locates the hash to rewrite
  # from the fetcher bound to `src`, and silently leaves a stale hash behind
  # when it finds anything else there. `hash` therefore covers the patched
  # tree, and changing the patch changes it.
  patch = ./patches/0001-expose-provider.patch;
in
mkTerraformBridgeProvider {
  inherit repo version cmdGen;
  src = fetchFromGitHub {
    name = "source-${repo}-${rev}";
    owner = "pulumi";
    inherit repo rev;
    hash = "sha256-W8HsiSyxHISBEiRSptDYpOtxm39ecFM+Ocpb3PK/uwc=";
    fetchSubmodules = true;
    postFetch = ''
      patch -d "$out/upstream" -p1 < ${patch}
    '';
  };
  vendorHash = "sha256-6n+VYf4S4HeDira2HzmTyZ1YUe1hj6KGV2B4d0Pr+OE=";
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
