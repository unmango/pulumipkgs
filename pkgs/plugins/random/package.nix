{
  lib,
  mkTerraformBridgeProvider,
}:
mkTerraformBridgeProvider rec {
  owner = "pulumi";
  repo = "pulumi-random";
  version = "4.21.1";
  rev = "v${version}";
  hash = "sha256-3fMikBF4LEWdbzcH3MfowWEKZdsY4nDww7/gxP8nWas=";
  vendorHash = "sha256-AYcm7WCSY734ldtd6QAqcHdYtaqn2u/BcBOgtJ8mzWk=";
  cmdGen = "pulumi-tfgen-random";
  cmdRes = "pulumi-resource-random";
  extraLdflags = [
    "-X github.com/pulumi/${repo}/provider/v4/pkg/version.Version=v${version}"
  ];
  meta = {
    description = "Pulumi provider that safely enables randomness for resources";
    mainProgram = "pulumi-resource-random";
    homepage = "https://github.com/pulumi/pulumi-random";
    license = lib.licenses.asl20;
  };
}
