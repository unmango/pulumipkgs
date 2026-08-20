{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule (finalAttrs: {
  pname = "pulumi-dotnet";
  version = "3.112.1";
  src = fetchFromGitHub {
    owner = "pulumi";
    repo = "pulumi-dotnet";
    tag = "v${finalAttrs.version}";
    hash = "sha256-eBtPev2mQMur9Snp2hVhk7EPF/AAT4UoFCO/fA8lKSA=";
  };
  sourceRoot = "${finalAttrs.src.name}/pulumi-language-dotnet";
  vendorHash = "sha256-LcK82+L2hjpMwno9Myc+9FDB354RO2QXKfMeJ95fqhU=";

  # The test suite shells out to the `dotnet` CLI, which is not available
  # in the Nix build sandbox.
  doCheck = false;
  ldflags = [
    "-s"
    "-w"
    "-X=github.com/pulumi/pulumi-dotnet/pulumi-language-dotnet/v3/version.Version=${finalAttrs.version}"
  ];
  meta = {
    homepage = "https://www.pulumi.com/docs/iac/languages-sdks/dotnet/";
    description = "Language host for Pulumi programs written in .NET";
    license = lib.licenses.asl20;
    mainProgram = "pulumi-language-dotnet";
  };
})
