{
  lib,
  buildGoModule,
  callPackage,
  fetchFromGitHub,
  fetchurl,
}:
let
  # The .NET codegen writes a logo.png beside each generated SDK's .csproj, and
  # upstream's getLogo() downloads it, so `pulumi package gen-sdk --language
  # dotnet` cannot run in a build sandbox. Fetch it here instead, where nix's
  # fixed-output fetcher is the one thing allowed network, and patch getLogo()
  # to read this vendored copy. The URL is upstream's own hardcoded default.
  defaultLogo = fetchurl {
    url = "https://raw.githubusercontent.com/pulumi/pulumi/dbc96206bec722b7791a22ff50e895ab7c0abdc0/sdk/dotnet/pulumi_logo_64x64.png";
    hash = "sha256-XqrP0xs/0mafCNTqALimp4SA9s23lGIcNY9Zyv9TT+k=";
  };
in
buildGoModule (finalAttrs: {
  pname = "pulumi-dotnet";
  version = "3.112.1";
  src = fetchFromGitHub {
    owner = "pulumi";
    repo = "pulumi-dotnet";
    tag = "v${finalAttrs.version}";
    hash = "sha256-eBtPev2mQMur9Snp2hVhk7EPF/AAT4UoFCO/fA8lKSA=";
  };
  sourceRoot = "${finalAttrs.src.name}/pulumi-language-dotnet";
  vendorHash = "sha256-LcK82+L2hjpMwno9Myc+9FDB354RO2QXKfMeJ95fqhU=";

  # Applied before postPatch, so the substitution below lands on the patched
  # file. Touches no go.mod/go.sum, so vendorHash is unaffected.
  patches = [ ./patches/offline-logo.patch ];

  postPatch = ''
    substituteInPlace codegen/gen.go \
      --subst-var-by pulumiLogo ${defaultLogo}
  '';

  # The test suite shells out to the `dotnet` CLI, which is not available
  # in the Nix build sandbox.
  doCheck = false;
  ldflags = [
    "-s"
    "-w"
    "-X=github.com/pulumi/pulumi-dotnet/pulumi-language-dotnet/v3/version.Version=${finalAttrs.version}"
  ];

  passthru = {
    # Exposed so the gen-sdk test can assert a generated logo.png is
    # byte-for-byte this file, which is what proves the patch took effect.
    pulumiLogo = defaultLogo;
    tests.genSdk = callPackage ./gen-sdk-test { };
  };

  meta = {
    homepage = "https://www.pulumi.com/docs/iac/languages-sdks/dotnet/";
    description = "Language host for Pulumi programs written in .NET";
    license = lib.licenses.asl20;
    mainProgram = "pulumi-language-dotnet";
  };
})
