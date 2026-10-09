{
  lib,
  mkTerraformBridgeProvider,
}:
mkTerraformBridgeProvider rec {
  owner = "pulumi";
  repo = "pulumi-azuread";
  version = "6.11.0";
  rev = "v${version}";
  hash = "sha256-Nyrb4lGW4OUOoRJ813Mcm9Ko0bJuP8FBwaEthz+v2QU=";
  vendorHash = "sha256-9sNEKqQghBBVLBDc1j4IA0KCex5ZnT9rljjYx7CVSoU=";
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
