{
  lib,
  mkPulumiPackage,
}:
mkPulumiPackage rec {
  owner = "pulumi";
  repo = "pulumi-azuread";
  version = "6.10.0";
  rev = "v${version}";
  hash = "sha256-euyozh+ySs0BU8D6B7xPXcZh65xr7UmwigIWR7OnqlE=";
  vendorHash = "sha256-gyBOy+BDlEU9V7RT72HaxjjMpacZE7cGtJkSCsHIdBw=";
  cmdGen = "pulumi-tfgen-azuread";
  cmdRes = "pulumi-resource-azuread";
  extraLdflags = [
    "-X github.com/pulumi/${repo}/provider/v6/pkg/version.Version=v${version}"
  ];
  meta = {
    description = "A Microsoft Azure Active Directory (Azure AD) Pulumi resource package";
    mainProgram = "pulumi-resource-azuread";
    homepage = "https://github.com/pulumi/pulumi-azuread";
    license = lib.licenses.asl20;
  };
}
