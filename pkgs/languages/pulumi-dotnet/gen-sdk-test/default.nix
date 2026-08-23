# A plain `pulumi-dotnet` build says nothing about whether .NET codegen still
# works offline: the language host builds and runs either way, and only
# `pulumi package gen-sdk --language dotnet` exercises getLogo(). This runs
# that, so the offline-logo patch dropping out is a build failure rather than
# something a consumer discovers in their own sandbox.
{
  lib,
  stdenvNoCC,
  pulumi,
  pulumi-dotnet,
}:
stdenvNoCC.mkDerivation {
  name = "pulumi-dotnet-gen-sdk-test";
  src = builtins.filterSource (name: _: !(lib.hasSuffix ".nix" name)) ./.;

  dontBuild = true;
  doCheck = true;

  # `pulumi-dotnet` here puts pulumi-language-dotnet on PATH, which is how the
  # CLI resolves a language plugin it hasn't downloaded (an "ambient" plugin).
  nativeCheckInputs = [
    pulumi
    pulumi-dotnet
  ];

  # gen-sdk talks to the language host over a loopback gRPC connection.
  __darwinAllowLocalNetworking = true;

  checkPhase = ''
    runHook preCheck

    export HOME=$(mktemp -d)
    export PULUMI_HOME=$HOME/.pulumi
    export PULUMI_SKIP_UPDATE_CHECK=1
    export PULUMI_DISABLE_AUTOMATIC_PLUGIN_ACQUISITION=1

    pulumi package gen-sdk --language dotnet --out sdk schema.json

    # schema.json sets an unresolvable logoUrl, so an unpatched codegen fails
    # here even outside a sandbox, rather than silently downloading a logo.
    cmp sdk/dotnet/logo.png ${pulumi-dotnet.pulumiLogo}

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    runHook postInstall
  '';
}
