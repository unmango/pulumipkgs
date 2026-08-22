{
  lib,
  runCommand,
  buildGoModule,
  mkTerraformBridgeProvider,
}:
let
  owner = "pulumi";
  repo = "pulumi-gitlab";
  version = "10.1.1";
  rev = "v${version}";
  hash = "sha256-vPi0U8K9ghMADAgwg9ncUv/qOekxRFhYx1Z+zaesv7w=";
  vendorHash = "sha256-eEYzS0bSaXPqz4qf1uPiwS1yvywprlDUaoYCZetaqMg=";
  cmdGen = "pulumi-tfgen-gitlab";
  cmdRes = "pulumi-resource-gitlab";
  extraLdflags = [
    "-X github.com/pulumi/${repo}/provider/v10/pkg/version.Version=v${version}"
  ];

  # provider/resources.go imports a `shim` package that upstream's own build
  # generates by patching the `upstream/` submodule at build time (see
  # pulumi-gitlab's `Makefile` `.make/upstream` target and
  # `scripts/upstream.sh`), rather than committing it to the submodule.
  # nixpkgs' mkPulumiPackage only threads postPatch/patches through to the
  # final provider build, not to the internal tfgen (`pulumi-gen`) build it
  # constructs for schema generation, so tfgen needs its own patched src.
  patch = ./patches/0001-expose-provider.patch;

  base = mkTerraformBridgeProvider rec {
    inherit
      owner
      repo
      version
      rev
      hash
      vendorHash
      cmdGen
      cmdRes
      extraLdflags
      ;
    fetchSubmodules = true;
    postPatch = ''
      chmod -R u+w ../upstream
      patch -d ../upstream -p1 < ${patch}
    '';
    # Same as the default upstream postConfigure, except schema generation
    # here also tries to bulk-convert doc examples from HCL by shelling out
    # to the `pulumi` CLI, which in turn needs to download a converter
    # plugin from GitHub releases -- network access the Nix sandbox doesn't
    # allow for a non-fixed-output derivation. `--skip-examples` opts out of
    # that step (doesn't affect generated resources/functions, only
    # translated doc examples). Same issue as pulumi-github.
    postConfigure = ''
      pushd ..

      chmod +w sdk/
      ${cmdGen} schema --skip-examples

      popd

      VERSION=v${version} go generate cmd/${cmdRes}/main.go
    '';
    meta = {
      description = "Pulumi provider to manage resources on GitLab";
      mainProgram = "pulumi-resource-gitlab";
      homepage = "https://github.com/pulumi/pulumi-gitlab";
      license = lib.licenses.asl20;
    };
  };

  patchedSrc = runCommand "source-${repo}-${rev}-patched" { } ''
    cp -r ${base.src} source
    chmod -R u+w source
    patch -d source/upstream -p1 < ${patch}
    mkdir -p $out
    cp -r source/. $out/
  '';

  pulumi-gen = buildGoModule {
    pname = cmdGen;
    inherit version vendorHash;
    src = patchedSrc;
    sourceRoot = "${patchedSrc.name}/provider";
    subPackages = [ "cmd/${cmdGen}" ];
    doCheck = false;
    ldflags = [
      "-s"
      "-w"
    ]
    ++ extraLdflags;
  };
in
base.overrideAttrs (old: {
  nativeBuildInputs =
    (builtins.filter (
      drv: !(lib.isDerivation drv && (drv.pname or "") == cmdGen)
    ) old.nativeBuildInputs)
    ++ [ pulumi-gen ];
})
