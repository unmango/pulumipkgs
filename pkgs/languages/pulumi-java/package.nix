{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule (finalAttrs: {
  pname = "pulumi-java";
  version = "1.37.3";
  src = fetchFromGitHub {
    owner = "pulumi";
    repo = "pulumi-java";
    tag = "v${finalAttrs.version}";
    hash = "sha256-yerN0quLCsd+1cIpJJEAkdQq4IiKw5LZUlc4krJm+1E=";
  };
  vendorHash = "sha256-806DuDvHx6R6fOpv/CPwd27q+RndsqdLVsLbhCPQpNY=";
  subPackages = [ "pkg/cmd/pulumi-language-java" ];
  # The language host's test suite expects a full checkout of the sibling
  # `pulumi/pulumi` proto sources, which aren't available in the sandboxed
  # build environment.
  doCheck = false;
  ldflags = [
    "-s"
    "-w"
    "-X=github.com/pulumi/pulumi-java/pkg/version.Version=${finalAttrs.version}"
  ];
  meta = {
    homepage = "https://www.pulumi.com/docs/iac/languages-sdks/java/";
    description = "Language host for Pulumi programs written in Java";
    license = lib.licenses.asl20;
    mainProgram = "pulumi-language-java";
  };
})
