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
    };
    mkTerraformBridgeProvider = pulumi2nixLib.mkTerraformBridgeProvider {
      pkgs = self;
    };
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
