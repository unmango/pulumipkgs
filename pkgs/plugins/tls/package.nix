{
  lib,
  mkTerraformBridgeProvider,
}:
mkTerraformBridgeProvider rec {
  owner = "pulumi";
  repo = "pulumi-tls";
  version = "5.6.0";
  rev = "v${version}";
  hash = "sha256-1pUpUQ3PeXPUxdpwk+Jb/ak68x3WDhSwyBESVYIg/ho=";
  vendorHash = "sha256-gS0+UiUX5P2vYWyGGJm9y1QY75fwzrR0bXzyrMRHKZ0=";
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
