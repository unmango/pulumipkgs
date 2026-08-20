{
  stdenv,
  fetchFromGitHub,
  fetchYarnDeps,
  yarnConfigHook,
}:
{
  owner,
  repo,
  version,
  rev,
  hash,
  yarnHash,
  meta,
}:
let
  src = fetchFromGitHub {
    inherit
      owner
      repo
      rev
      hash
      ;
  };
in
stdenv.mkDerivation {
  pname = repo;
  inherit version src meta;

  yarnOfflineCache = fetchYarnDeps {
    inherit src;
    hash = yarnHash;
  };

  nativeBuildInputs = [ yarnConfigHook ];

  dontBuild = true;

  # No compile step: source-based plugins ship as source, not a build
  # artifact. $out is the plugin directory `pulumi package add` reads
  # directly, with node_modules already populated so it works offline.
  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r ./. "$out/"

    runHook postInstall
  '';
}
