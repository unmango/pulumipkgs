{
  lib,
  callPackage,
  buildGoModule,
  pulumi,
  nixpkgsPath,
}:
callPackage "${nixpkgsPath}/pkgs/by-name/pu/pulumi/plugins/pulumi-bun/package.nix" (
  # nixpkgs builds pulumi-language-bun with `vendorHash = null`, which expects a
  # committed vendor/ directory that upstream doesn't have. At pulumi 3.268.0
  # the module's go.mod requires go-ruleguard/dsl (as a `tool`), and the build
  # stops with "inconsistent vendoring". This hash matches only that version's
  # module graph, so the override is gated on it: any other `pulumi` (a newer
  # nixpkgs, or an overlay consumer's own) gets nixpkgs' file untouched. Once
  # nixpkgs fixes it, delete the override and go back to a bare re-export.
  lib.optionalAttrs (pulumi.version == "3.268.0") {
    buildGoModule =
      f:
      (buildGoModule f).overrideAttrs {
        vendorHash = "sha256-Fps7U7ORVPaOloJCAiz9sxqinZIxQmYxPv7eQoiR4hk=";
      };
  }
)
