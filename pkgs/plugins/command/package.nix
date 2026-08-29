{
  lib,
  mkPulumiPackage,
}:
mkPulumiPackage rec {
  owner = "pulumi";
  repo = "pulumi-command";
  version = "1.2.1";
  rev = "v${version}";
  hash = "sha256-1RXTim8/Bge0NwKNRKhVxWtV1HfCgdfX+9IYJkMjq70=";
  vendorHash = "sha256-FoGGfRFcH2FaO1n86pPnAN9Z3cTQv5hWEtxpRKgZIk4=";
  cmdGen = "pulumi-gen-command";
  cmdRes = "pulumi-resource-command";
  extraLdflags = [
    "-X github.com/pulumi/${repo}/provider/pkg/version.Version=v${version}"
  ];

  meta = {
    description = "Pulumi provider to execute commands and scripts either locally or remotely as part of the Pulumi resource model";
    mainProgram = "pulumi-resource-command";
    homepage = "https://github.com/pulumi/pulumi-command";
    license = lib.licenses.asl20;
  };
}
