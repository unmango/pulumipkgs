#!/usr/bin/env bash
# Update automation (docs/spec.md §5, §5a): for every resource provider in
# data/supported-packages.json, compare its pinned version against the
# Pulumi registry; for every bespoke-build language runtime under
# pkgs/languages, compare its pinned version against its GitHub releases.
# Open a pull request for each package that's behind.
set -uo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root" || exit 1

allowlist=data/supported-packages.json
registry_base="https://raw.githubusercontent.com/pulumi/registry/master/themes/default/data/registry/packages"

failures=()
updates=()

# Rewrites version/hash/vendorHash via nix-update, builds the result, and
# opens a PR on success (or discards the change and records a failure).
attempt_bump() {
  local name="$1" package_nix="$2" old_version="$3" new_version="$4" attr="$5" pr_body="$6"

  if ! nix-update "pulumiPackages.$attr" --version="$new_version"; then
    echo "  nix-update failed"
    git checkout -- "$package_nix"
    failures+=("$name: nix-update failed ($old_version -> $new_version)")
    return
  fi

  if ! nix build ".#pulumiPackages.$attr"; then
    echo "  build failed, discarding change"
    git checkout -- "$package_nix"
    failures+=("$name: build failed ($old_version -> $new_version)")
    return
  fi

  local branch="update-$name-$new_version"
  git checkout -b "$branch"
  git add "$package_nix"
  git commit -m "$name: $old_version -> $new_version"

  if ! git push -u origin "$branch"; then
    echo "  push failed"
    git checkout -
    git branch -D "$branch"
    failures+=("$name: git push failed ($old_version -> $new_version)")
    return
  fi

  if ! gh pr create \
    --title "$name: $old_version -> $new_version" \
    --body "$pr_body" \
    --head "$branch"; then
    echo "  gh pr create failed"
    git checkout -
    failures+=("$name: gh pr create failed ($old_version -> $new_version)")
    return
  fi

  git checkout -
  git branch -D "$branch"

  updates+=("$name: $old_version -> $new_version")
}

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
  attempt_bump "$name" "$package_nix" "$pinned_version" "$registry_version" "$name" \
    "Automated update from the Pulumi registry."
done

echo
echo "== language runtimes =="
for dir in pkgs/languages/pulumi-*/; do
  name=$(basename "$dir")
  echo "== $name =="

  package_nix="${dir}package.nix"
  pinned_version=$(sed -n 's/^[[:space:]]*version = "\(.*\)";/\1/p' "$package_nix" | head -n1)
  if [[ -z "$pinned_version" ]]; then
    echo "  skip: re-export, no local pin"
    continue
  fi

  latest_version=$(gh api "repos/pulumi/$name/releases/latest" --jq '.tag_name' 2>/dev/null | sed 's/^v//')
  if [[ -z "$latest_version" ]]; then
    echo "  skip: failed to fetch latest release for pulumi/$name"
    failures+=("$name: GitHub release fetch failed")
    continue
  fi

  if [[ "$latest_version" == "$pinned_version" ]]; then
    echo "  up to date ($pinned_version)"
    continue
  fi

  echo "  $pinned_version -> $latest_version"
  attempt_bump "$name" "$package_nix" "$pinned_version" "$latest_version" "$name" \
    "Automated update from the pulumi/$name GitHub releases."
done

echo
echo "== summary =="
echo "updated: ${#updates[@]}"
printf '  %s\n' "${updates[@]}"
echo "failed: ${#failures[@]}"
printf '  %s\n' "${failures[@]}"
