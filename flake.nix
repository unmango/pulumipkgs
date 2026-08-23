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

          # Packages left out of the joined `default` environment because
          # another package in the set installs the same file name. Only one
          # can win on PATH, so the choice is made here rather than left to
          # whichever `symlinkJoin` happens to link first. Each excluded
          # package is still built by `checks` and buildable on its own.
          #
          # pulumi-gestalt and pulumi-rust are two community implementations
          # of the same Pulumi language runtime, both installing
          # bin/pulumi-language-rust; pulumi-rust is the maintained one.
          joinConflicts = [ "pulumi-gestalt" ];

          # `passthru.tests` entries left out of `checks`, per package. Only for
          # tests inherited from a nixpkgs re-export that fail for reasons that
          # have nothing to do with this flake; a test written here that fails
          # is a bug to fix, not to list.
          #
          # pulumi-python's smokeTest comes from nixpkgs' own
          # pkgs/by-name/pu/pulumi/plugins/pulumi-python and fails identically
          # as `nixpkgs#pulumiPackages.pulumi-python.tests.smokeTest` on the
          # pinned nixpkgs: python3Packages.pulumi imports `packaging`, which
          # isn't among its dependencies.
          testExclusions = {
            pulumi-python = [ "smokeTest" ];
          };
        in
        {
          packages = pulumiPackages // {
            default = pkgs.symlinkJoin {
              name = "pulumipkgs";
              paths = builtins.attrValues (removeAttrs pulumiPackages joinConflicts);
            };
          };

          legacyPackages = inputs'.nixpkgs.legacyPackages.extend (
            final: _prev: {
              pulumiPackages = mkPulumiPackages final;
            }
          );

          # Every package's own build, plus any `passthru.tests` a package
          # carries: a build alone can't cover behavior that only shows up when
          # the built binary is run (see pulumi-dotnet's gen-sdk test).
          checks =
            lib.mapAttrs' (name: pkg: lib.nameValuePair "pulumiPackages-${name}" pkg) pulumiPackages
            // lib.concatMapAttrs (
              name: pkg:
              lib.mapAttrs' (testName: test: lib.nameValuePair "pulumiPackages-${name}-${testName}" test) (
                lib.filterAttrs (
                  testName: test: lib.isDerivation test && !(builtins.elem testName (testExclusions.${name} or [ ]))
                ) (pkg.passthru.tests or { })
              )
            ) pulumiPackages;

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
