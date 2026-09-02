{
  lib,
  mkTerraformBridgeProvider,
}:
# Neither under the `pulumi` org nor published to the Pulumi registry: upstream
# distributes this through its own GitHub releases, so its
# data/supported-packages.json entry sets `"source": "github"` (spec §5).
mkTerraformBridgeProvider rec {
  owner = "UnstoppableMango";
  repo = "pulumi-provider-git";
  version = "0.0.2";
  rev = "v${version}";
  hash = "sha256-gLkcvYV//4wj2bsX7OIbDYWZmonX/Es1c+ZQOxg6j1g=";
  vendorHash = "sha256-9Cz3X57TokfHCUtMEEDhVQ0eHgTsSgweoZwLhd/94mQ=";
  cmdGen = "pulumi-tfgen-git";
  cmdRes = "pulumi-resource-git";
  extraLdflags = [
    "-X github.com/${owner}/${repo}/provider/pkg/version.Version=v${version}"
  ];
  meta = {
    description = "Pulumi provider for declaring and reconciling the state of git repositories";
    mainProgram = "pulumi-resource-git";
    homepage = "https://github.com/UnstoppableMango/pulumi-provider-git";
    license = lib.licenses.asl20;
  };
}
