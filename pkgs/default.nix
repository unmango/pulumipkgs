{
  pkgs,
  nixpkgsPath,
  pulumi2nixLib,
}:
let
  inherit (pkgs) lib generateSplicesForMkScope;
  inherit (pkgs) makeScopeWithSplicing';
in
makeScopeWithSplicing' {
  otherSplices = generateSplicesForMkScope "pulumiPackages";
  extra = self: {
    inherit nixpkgsPath;
    mkPulumiPackage = pulumi2nixLib.mkPulumiPackage {
      pkgs = self;
      inherit nixpkgsPath;
    };
    # pulumi2nix's own mkTerraformBridgeProvider is "the terraform-bridge base
    # builder on its own, without any SDK layering" (lib/default.nix) - a
    # tfbridge provider with e.g. nodejsArgs (pulumiPackages.github) crashes
    # going through it directly ("cannot coerce a set to a string", nodejsArgs
    # falls straight through to the raw derivation attrs). mkPulumiPackage
    # *does* layer <lang>Args SDKs, but hardcodes the native schema
    # convention (`cmdGen schema.json --version`) rather than tfgen's
    # (`cmdGen schema --out .`). Compose the two: build via mkPulumiPackage
    # (correct build + SDK layering), then swap passthru.schema for the
    # tfgen-flavored one - the same passthru.schema override
    # mkTerraformBridgeProvider itself applies internally. No public
    # pulumi2nix builder composes tfbridge-correct schema with SDK layering;
    # filed as https://github.com/UnstoppableMango/pulumi2nix/issues/28.
    mkTerraformBridgeProvider =
      let
        mkPkg = pulumi2nixLib.mkPulumiPackage {
          pkgs = self;
          inherit nixpkgsPath;
        };
        mkTfSchema = pulumi2nixLib.mkTerraformBridgeSchema { pkgs = self; };
      in
      args:
      (mkPkg args).overrideAttrs (old: {
        passthru = old.passthru // {
          schema = mkTfSchema args;
        };
      });
    testResourceSchema =
      self.callPackage "${nixpkgsPath}/pkgs/by-name/pu/pulumi/extra/test-resource-schema.nix"
        { };
    pulumiTestHook = "${nixpkgsPath}/pkgs/by-name/pu/pulumi/extra/pulumi-test-hook.sh";
  };
  f =
    self:
    lib.packagesFromDirectoryRecursive {
      inherit (self) callPackage;
      directory = ./plugins;
    }
    // lib.packagesFromDirectoryRecursive {
      inherit (self) callPackage;
      directory = ./languages;
    };
}
