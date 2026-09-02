{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule (finalAttrs: {
  pname = "pulumi-yaml";
  version = "1.38.5";
  src = fetchFromGitHub {
    owner = "pulumi";
    repo = "pulumi-yaml";
    tag = "v${finalAttrs.version}";
    hash = "sha256-E1FaRhav1oGr7VhFQLScQgJTuxjSxHrv3Ic4Ar0q45E=";
  };
  vendorHash = "sha256-+H1GBu8CENS3TILJaIV+B9MZW3zZaDNrObqxy3nL7wg=";
  subPackages = [ "cmd/pulumi-language-yaml" ];

  # The test suite spins up gRPC servers and hangs waiting on network
  # access that is not available in the Nix build sandbox.
  doCheck = false;
  ldflags = [
    "-s"
    "-w"
    "-X=github.com/pulumi/pulumi-yaml/pkg/version.Version=${finalAttrs.version}"
  ];
  meta = {
    homepage = "https://www.pulumi.com/docs/iac/languages-sdks/yaml/";
    description = "Language host for Pulumi programs written in YAML/JSON";
    license = lib.licenses.asl20;
    mainProgram = "pulumi-language-yaml";
  };
})
