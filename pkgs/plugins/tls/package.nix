{
  lib,
  mkTerraformBridgeProvider,
}:
mkTerraformBridgeProvider rec {
  owner = "pulumi";
  repo = "pulumi-tls";
  version = "5.5.1";
  rev = "v${version}";
  hash = "sha256-/tfJTdoDzx64MWV0DBxXTClsAfRAZlCSClEvqozrxu0=";
  vendorHash = "sha256-hGGkB//vTFRVdrcjE3surKLSc2OScaSGC3Fg5p8H/VM=";
  cmdGen = "pulumi-tfgen-tls";
  cmdRes = "pulumi-resource-tls";
  extraLdflags = [
    "-X github.com/pulumi/${repo}/provider/v5/pkg/version.Version=v${version}"
  ];
  meta = {
    description = "Pulumi provider for generating self-signed certificates and other TLS/PKI-related resources";
    mainProgram = "pulumi-resource-tls";
    homepage = "https://github.com/pulumi/pulumi-tls";
    license = lib.licenses.asl20;
  };
}
