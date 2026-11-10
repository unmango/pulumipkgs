{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule (finalAttrs: {
  pname = "pulumi-yaml";
  version = "1.39.0";
  src = fetchFromGitHub {
    owner = "pulumi";
    repo = "pulumi-yaml";
    tag = "v${finalAttrs.version}";
    hash = "sha256-mIDcH4mGsPC/6dpmxCgcEeU4Vso7fGwo2Ruk7W5sP7g=";
  };
  vendorHash = "sha256-EI+2i4/yhV/K49SIM/QG4w6Vy583hWh9GqljWHkl+3o=";
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
