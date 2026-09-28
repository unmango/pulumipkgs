{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule (finalAttrs: {
  pname = "pulumi-yaml";
  version = "1.38.8";
  src = fetchFromGitHub {
    owner = "pulumi";
    repo = "pulumi-yaml";
    tag = "v${finalAttrs.version}";
    hash = "sha256-X60d4LLOKF1xYL0bdCg+GLj7XPSafh0pSuz1kV8Ozqs=";
  };
  vendorHash = "sha256-B/+9/pWOapvdyyuPDg8JDORtDsSiy7TncBIY2ShcN3k=";
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
