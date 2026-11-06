{
  lib,
  mkTerraformBridgeProvider,
}:
mkTerraformBridgeProvider rec {
  owner = "pulumi";
  repo = "pulumi-tls";
  version = "5.6.3";
  rev = "v${version}";
  hash = "sha256-M7zxVPFl2UQ6jQ+l6s+2pa7CLLbolWEwHSJhm2hLhZ0=";
  vendorHash = "sha256-1RaXDgOnxLoHl947JiFPnY8hiHa4ZVWDAb5fgtXkfrs=";
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
