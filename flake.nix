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

    pulumi2nix = {
      url = "github:UnstoppableMango/pulumi2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    let
      mkPulumiPackages =
        pkgs:
        import ./pkgs {
          inherit pkgs;
          nixpkgsPath = inputs.nixpkgs.outPath;
          pulumi2nixLib = inputs.pulumi2nix.lib;
        };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [ inputs.treefmt-nix.flakeModule ];

      flake.overlays.default = final: _prev: {
        pulumiPackages = mkPulumiPackages final;
      };

      perSystem =
        {
          inputs',
          pkgs,
          lib,
          ...
        }:
        let
          pulumiPackages = lib.filterAttrs (_: lib.isDerivation) (
            mkPulumiPackages inputs'.nixpkgs.legacyPackages
          );
        in
        {
          packages = pulumiPackages // {
            default = pkgs.symlinkJoin {
              name = "pulumipkgs";
              paths = builtins.attrValues pulumiPackages;
            };
          };

          legacyPackages = inputs'.nixpkgs.legacyPackages.extend (
            final: _prev: {
              pulumiPackages = mkPulumiPackages final;
            }
          );

          checks = lib.mapAttrs' (name: pkg: lib.nameValuePair "pulumiPackages-${name}" pkg) pulumiPackages;

          devShells.default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              bash
              curl
              gh
              git
              gnumake
              jq
              nixfmt
              nix-update
            ];
          };

          treefmt.programs = {
            actionlint.enable = true;
            mdformat.enable = true;
            nixfmt.enable = true;
            shellcheck.enable = true;
          };

          treefmt.settings.formatter.mdformat.excludes = [
            ".agents/skills/**"
            ".claude/skills/**"
          ];
        };
    };
}
