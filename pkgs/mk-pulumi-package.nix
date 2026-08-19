{
  lib,
  callPackage,
  fetchFromGitHub,
  buildNpmPackage,
  nixpkgsPath,
}:
let
  mkUpstreamPackage =
    callPackage "${nixpkgsPath}/pkgs/by-name/pu/pulumi/extra/mk-pulumi-package.nix"
      { };

  # Pulumi's nodejs codegen always emits an SDK that compiles to `bin/`
  # (tsconfig.json's outDir) and is published from `bin/` once package.json
  # (version-substituted) and the license/readme are copied alongside the
  # compiled output, not from the SDK source root. This mirrors that
  # convention; it's the same shape used by every provider's Node.js SDK, not
  # something specific to one provider.
  mkNodejsPackage =
    {
      meta,
      pname,
      src,
      version,
      lockFile,
      ...
    }@args:
    buildNpmPackage (
      {
        inherit
          meta
          pname
          src
          version
          ;

        sourceRoot = "${src.name}/sdk/nodejs";

        postPatch = ''
          cp ${lockFile} package-lock.json
          sed -i \
            -e 's/"version": ".*"/"version": "${version}"/' \
            package.json
        '';

        npmBuildScript = "build";

        postBuild = ''
          cp package.json bin/
          cp ../../README.md ../../LICENSE bin/ 2>/dev/null || true
        '';

        installPhase = ''
          runHook preInstall

          pkgName=$(node -p "require('./bin/package.json').name")
          packageOut="$out/lib/node_modules/$pkgName"
          mkdir -p "$packageOut"
          cp -r bin/. "$packageOut/"

          if [ -z "''${dontNpmPrune-}" ]; then
            npm prune --omit=dev --no-save
          fi
          cp -r node_modules "$packageOut/node_modules"

          runHook postInstall
        '';
      }
      // (lib.removeAttrs args [ "lockFile" ])
    );

  # Only invoked for `<lang>Args` attributes the caller actually passes.
  # Languages beyond nodejs stay unimplemented, added opportunistically as
  # providers need them (see docs/roadmap.md).
  mkLangPackage =
    lang: args:
    if lang == "nodejs" then
      mkNodejsPackage args
    else
      throw "pkgs/mk-pulumi-package.nix: no builder implemented yet for SDK language '${lang}' (only pythonArgs and nodejsArgs are supported)";
in
args@{ ... }:
let
  langArgNames = lib.filter (name: name != "pythonArgs" && lib.hasSuffix "Args" name) (
    builtins.attrNames args
  );

  # Upstream's mk-pulumi-package.nix fetches its own `src` internally and
  # doesn't expose it via passthru, so a source fetch is needed here too for
  # any <lang>Args builder that needs it (e.g. to read sdk/nodejs). Same
  # inputs as upstream's fetch, so it dedupes at the store level rather than
  # actually fetching twice.
  src = fetchFromGitHub {
    name = "source-${args.repo}-${args.rev}";
    inherit (args)
      owner
      repo
      rev
      hash
      ;
    fetchSubmodules = args.fetchSubmodules or false;
  };

  extraSdks = lib.listToAttrs (
    map (argName: {
      name = lib.removeSuffix "Args" argName;
      value = mkLangPackage (lib.removeSuffix "Args" argName) (
        {
          inherit (args) meta version;
          inherit src;
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
