{
  lib,
  mkTerraformBridgeProvider,
}:
mkTerraformBridgeProvider rec {
  owner = "pulumi";
  repo = "pulumi-azuread";
  version = "6.11.1";
  rev = "v${version}";
  hash = "sha256-DCwBXFiZhz++74NSwzsT9KpyWm62hw3uIgk0rQQilGM=";
  vendorHash = "sha256-sDLYK2pdheu1y6bfvqFRCtcgXZVHFc70Xt9Tpy2ghAQ=";
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
