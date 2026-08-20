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
  extra =
    self:
    let
      pulumi2nix = pulumi2nixLib { pkgs = pkgs // self; };
    in
    {
      inherit nixpkgsPath;
      inherit (pulumi2nix) mkPulumiPackage mkTerraformBridgeProvider;
      mkComponentPackage = self.callPackage ./mk-component-package.nix { };
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
    }
    // lib.packagesFromDirectoryRecursive {
      inherit (self) callPackage;
      directory = ./components;
    };
}
