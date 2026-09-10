{
  lib,
  fetchFromGitHub,
  buildGoModule,
}:
buildGoModule rec {
  pname = "pulumi-resource-terraform-provider";
  version = "1.1.3";

  # pulumi/pulumi-terraform-provider only hosts docs and releases; the real
  # source lives in pulumi/pulumi-terraform-bridge's `dynamic/` folder. This
  # commit is the one the v1.1.3 release notes state it was generated from.
  src = fetchFromGitHub {
    owner = "pulumi";
    repo = "pulumi-terraform-bridge";
    rev = "484f8987228cbec779e11f593bc48c79c49d4f08";
    hash = "sha256-NGZONXglwkyptkLVdXVaoWCqvYY4+UAII9KFpD9aRss=";
  };

  vendorHash = "sha256-cVFwjrL3FDeXkKz/wAyqjsY99RAN0ed3NBWviBq8aV0=";
  subPackages = [ "dynamic" ];
  env.CGO_ENABLED = 0;

  # dynamic's test suite spawns real `pulumi` stacks via providertest/pulumitest,
  # which needs network access and a working Pulumi CLI environment - not viable
  # inside the build sandbox.
  doCheck = false;

  # Matches pulumi-terraform-provider's .goreleaser.yml build config.
  ldflags = [
    "-X google.golang.org/protobuf/reflect/protoregistry.conflictPolicy=ignore"
    "-X github.com/pulumi/pulumi-terraform-bridge/v3/dynamic/version.version=v${version}"
  ];

  postInstall = ''
    mv $out/bin/dynamic $out/bin/pulumi-resource-terraform-provider
  '';

  meta = {
    description = "Pulumi's generic dynamic bridge for using any Terraform provider as a Pulumi provider";
    mainProgram = "pulumi-resource-terraform-provider";
    homepage = "https://github.com/pulumi/pulumi-terraform-provider";
    license = lib.licenses.asl20;
  };
}
