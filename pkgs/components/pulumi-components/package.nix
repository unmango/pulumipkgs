{ mkComponentPackage, lib }:
mkComponentPackage {
  owner = "UnstoppableMango";
  repo = "pulumi-components";
  version = "unstable-2026-08-19";
  rev = "39f674ced396125674cd665c47d2601ae914496a";
  hash = "sha256-Lvbho2SYIcqN2jcfqysArf/guv3YwU2k1uWn7tRRJQ4=";
  yarnHash = "sha256-Pqp04NR2DSyW++iu1xBmWscr69Pfb9QdUtrP5dnGTHA=";
  meta = {
    description = "Reusable Pulumi component resources";
    homepage = "https://github.com/UnstoppableMango/pulumi-components";
    license = lib.licenses.mit;
  };
}
