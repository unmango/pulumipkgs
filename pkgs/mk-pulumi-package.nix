{
  lib,
  callPackage,
  nixpkgsPath,
}:
let
  mkUpstreamPackage =
    callPackage "${nixpkgsPath}/pkgs/by-name/pu/pulumi/extra/mk-pulumi-package.nix"
      { };

  # Placeholder: no builder exists yet for SDK languages other than Python.
  # Always throws. Only invoked for `<lang>Args` attributes the caller
  # actually passes.
  mkLangPackage =
    lang: _args:
    throw "pkgs/mk-pulumi-package.nix: no builder implemented yet for SDK language '${lang}' (only pythonArgs is supported upstream)";
in
args@{ ... }:
let
  langArgNames = lib.filter (name: name != "pythonArgs" && lib.hasSuffix "Args" name) (
    builtins.attrNames args
  );

  extraSdks = lib.listToAttrs (
    map (argName: {
      name = lib.removeSuffix "Args" argName;
      value = mkLangPackage (lib.removeSuffix "Args" argName) (
        {
          inherit (args) meta version;
          pname = args.repo;
        }
        // args.${argName}
      );
    }) langArgNames
  );

  base = mkUpstreamPackage (removeAttrs args langArgNames);
in
if extraSdks == { } then
  base
else
  base
  // {
    passthru = base.passthru // {
      sdks = base.passthru.sdks // extraSdks;
    };
  }
