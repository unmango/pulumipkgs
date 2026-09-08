{
  lib,
  mkTerraformBridgeProvider,
}:
mkTerraformBridgeProvider rec {
  owner = "pulumi";
  repo = "pulumi-azuread";
  version = "6.10.1";
  rev = "v${version}";
  hash = "sha256-aUKpFsoJzmbTUAFQGsc8NI15d+D/zMUUi8Jv/y29ueY=";
  vendorHash = "sha256-zk04UV2ijwvAbp62VnecOIU/+4H8+aovkTyN0+YI0hY=";
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
