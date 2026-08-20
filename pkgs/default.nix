{ pkgs, nixpkgsPath }:
let
  inherit (pkgs) lib generateSplicesForMkScope;
  inherit (pkgs) makeScopeWithSplicing';
in
makeScopeWithSplicing' {
  otherSplices = generateSplicesForMkScope "pulumiPackages";
  extra = self: {
    inherit nixpkgsPath;
    mkPulumiPackage = self.callPackage ./mk-pulumi-package.nix { inherit nixpkgsPath; };
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
    };
}
