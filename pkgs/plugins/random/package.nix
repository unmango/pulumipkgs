{
  lib,
  mkTerraformBridgeProvider,
}:
mkTerraformBridgeProvider rec {
  owner = "pulumi";
  repo = "pulumi-random";
  version = "4.21.6";
  rev = "v${version}";
  hash = "sha256-FnEva1s9D9aARoR3InNXS74EZZv9QlCP6HMvqHpwcfo=";
  vendorHash = "sha256-WwWDDCtRNyFhkTyQo2ZBbMMKo7q55KJjGanOWBbvwwY=";
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
