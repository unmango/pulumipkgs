{
  description = "A Nix flake exposing a package set of Pulumi provider plugins";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/triplet";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [ inputs.treefmt-nix.flakeModule ];

      perSystem =
        { inputs', self', pkgs, lib, system, ... }:
        let
          mkPulumiPackages =
            pkgs:
            import ./pkgs {
              inherit pkgs;
              nixpkgsPath = inputs.nixpkgs.outPath;
            };
        in
        {
          overlays.default = final: _prev: {
            pulumiPackages = mkPulumiPackages final;
          };

          # `packages.<system>` must, per the flake schema `nix flake check` enforces,
          # contain only derivations directly - so it's the flattened form
          # (`nix build .#random`). `legacyPackages.<system>.pulumiPackages` carries
          # the nested scope so `nix build .#pulumiPackages.<name>` (spec §5) also
          # works, since `nix build` falls back to `legacyPackages` when an
          # attribute path isn't found under `packages`.
          packages =
            lib.filterAttrs (_: lib.isDerivation) (mkPulumiPackages inputs'.nixpkgs.legacyPackages);

          legacyPackages =
            inputs'.nixpkgs.legacyPackages.extend self'.overlays.default;

          checks =
            lib.mapAttrs' (
              name: pkg: lib.nameValuePair "pulumiPackages-${name}" pkg
            ) self'.packages;

          devShells.default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              gnumake
              nixfmt
            ];
          };

          treefmt.programs = {
            nixfmt.enable = true;
          };
        };
    };
}
