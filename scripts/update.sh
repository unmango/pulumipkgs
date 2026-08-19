#!/usr/bin/env bash
# Update automation (docs/spec.md §5): for every package in
# data/supported-packages.json, compare its pinned version against the
# Pulumi registry, and open a pull request for each package that's behind.
set -uo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

allowlist=data/supported-packages.json
registry_base="https://raw.githubusercontent.com/pulumi/registry/master/themes/default/data/registry/packages"

failures=()
updates=()

mapfile -t names < <(jq -r 'keys[]' "$allowlist")
for name in "${names[@]}"; do
  echo "== $name =="

  package_nix="pkgs/plugins/$name/package.nix"
  if [[ ! -f "$package_nix" ]]; then
    echo "  skip: $package_nix does not exist"
    failures+=("$name: missing $package_nix")
    continue
  fi

  registry_yaml=$(curl -fsSL "$registry_base/$name.yaml") || {
    echo "  skip: failed to fetch registry metadata"
    failures+=("$name: registry fetch failed")
    continue
  }

  registry_version=$(printf '%s\n' "$registry_yaml" | sed -n 's/^version:[[:space:]]*v\{0,1\}//p' | head -n1)
  if [[ -z "$registry_version" ]]; then
    echo "  skip: could not parse version from registry metadata"
    failures+=("$name: unparseable registry version")
    continue
  fi

  pinned_version=$(sed -n 's/^[[:space:]]*version = "\(.*\)";/\1/p' "$package_nix" | head -n1)
  if [[ -z "$pinned_version" ]]; then
    echo "  skip: could not parse pinned version from $package_nix"
    failures+=("$name: unparseable pinned version")
    continue
  fi

  if [[ "$registry_version" == "$pinned_version" ]]; then
    echo "  up to date ($pinned_version)"
    continue
  fi

  echo "  $pinned_version -> $registry_version"

  if ! nix-update "pulumiPackages.$name" --version="$registry_version"; then
    echo "  nix-update failed"
    git checkout -- "$package_nix"
    failures+=("$name: nix-update failed ($pinned_version -> $registry_version)")
    continue
  fi

  if ! nix build ".#pulumiPackages.$name"; then
    echo "  build failed, discarding change"
    git checkout -- "$package_nix"
    failures+=("$name: build failed ($pinned_version -> $registry_version)")
    continue
  fi

  branch="update-$name-$registry_version"
  git checkout -b "$branch"
  git add "$package_nix"
  git commit -m "$name: $pinned_version -> $registry_version"

  if ! git push -u origin "$branch"; then
    echo "  push failed"
    git checkout -
    git branch -D "$branch"
    failures+=("$name: git push failed ($pinned_version -> $registry_version)")
    continue
  fi

  if ! gh pr create \
    --title "$name: $pinned_version -> $registry_version" \
    --body "Automated update from the Pulumi registry." \
    --head "$branch"; then
    echo "  gh pr create failed"
    git checkout -
    failures+=("$name: gh pr create failed ($pinned_version -> $registry_version)")
    continue
  fi

  git checkout -
  git branch -D "$branch"

  updates+=("$name: $pinned_version -> $registry_version")
done

echo
echo "== summary =="
echo "updated: ${#updates[@]}"
printf '  %s\n' "${updates[@]}"
echo "failed: ${#failures[@]}"
printf '  %s\n' "${failures[@]}"
