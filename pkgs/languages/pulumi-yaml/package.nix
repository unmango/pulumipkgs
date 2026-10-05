{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule (finalAttrs: {
  pname = "pulumi-yaml";
  version = "1.38.9";
  src = fetchFromGitHub {
    owner = "pulumi";
    repo = "pulumi-yaml";
    tag = "v${finalAttrs.version}";
    hash = "sha256-ONyda7U2Z8xsZXyw++oyfRB1dM0rRYzERal3M23W5+o=";
  };
  vendorHash = "sha256-q1XZ20OlgpgnXjuzN0LIYv/5AuD30M7QJZHO1c5Nz5A=";
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
