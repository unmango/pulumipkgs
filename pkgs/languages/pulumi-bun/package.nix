{
  callPackage,
  buildGoModule,
  nixpkgsPath,
}:
callPackage "${nixpkgsPath}/pkgs/by-name/pu/pulumi/plugins/pulumi-bun/package.nix" {
  # nixpkgs builds pulumi-language-bun with `vendorHash = null`, which expects a
  # committed vendor/ directory that upstream doesn't have. At pulumi 3.268.0
  # the module's go.mod requires go-ruleguard/dsl (as a `tool`), and the build
  # stops with "inconsistent vendoring". Supply a real vendorHash until nixpkgs
  # does, then drop this override and go back to a bare re-export.
  buildGoModule =
    f:
    (buildGoModule f).overrideAttrs {
      vendorHash = "sha256-Fps7U7ORVPaOloJCAiz9sxqinZIxQmYxPv7eQoiR4hk=";
    };
}
