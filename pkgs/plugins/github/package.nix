{
  lib,
  mkPulumiPackage,
}:
mkPulumiPackage rec {
  owner = "pulumi";
  repo = "pulumi-github";
  version = "6.15.0";
  rev = "v${version}";
  hash = "sha256-yZQra5xBPpuhR0furKvscBOigoolKilCi5m4HpmZBno=";
  vendorHash = "sha256-5M6yeMuoNwDtPzk7ykq2PlGnq2/UiMErduvOuX7hcoo=";
  cmdGen = "pulumi-tfgen-github";
  cmdRes = "pulumi-resource-github";
  extraLdflags = [
    "-X github.com/pulumi/${repo}/provider/v6/pkg/version.Version=v${version}"
  ];
  # provider/go.mod replaces the upstream Terraform provider module with a
  # git submodule (`upstream/`), which a plain tarball download doesn't
  # include.
  fetchSubmodules = true;
  # Same as the default upstream postConfigure, except schema generation
  # here also tries to bulk-convert doc examples from HCL by shelling out to
  # the `pulumi` CLI, which in turn needs to download a converter plugin
  # from GitHub releases — network access the Nix sandbox doesn't allow for
  # a non-fixed-output derivation. `--skip-examples` opts out of that step
  # (this doesn't affect the generated resources/functions, only translated
  # doc examples). Not needed by command/random/tls, whose bridge versions
  # or content don't hit this path.
  postConfigure = ''
    pushd ..

    chmod +w sdk/
    ${cmdGen} schema --skip-examples

    popd

    VERSION=v${version} go generate cmd/${cmdRes}/main.go
  '';
  nodejsArgs = {
    lockFile = ./sdk-nodejs-package-lock.json;
    npmDepsHash = "sha256-PXNA83e1ZDQSO/Tof9ZgXkxXI8wLSTjR4fnTdqRtfcw=";
  };
  meta = {
    description = "Pulumi provider to manage resources on GitHub";
    mainProgram = "pulumi-resource-github";
    homepage = "https://github.com/pulumi/pulumi-github";
    license = lib.licenses.asl20;
  };
}
