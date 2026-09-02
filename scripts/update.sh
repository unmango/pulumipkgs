#!/usr/bin/env bash
# Update automation (docs/spec.md §5, §5a): compare each supported provider
# against the Pulumi registry and each pinned language runtime against its
# GitHub releases, opening a pull request for every package that's behind.
set -uo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root" || exit 1

allowlist=data/supported-packages.json
registry_base="https://raw.githubusercontent.com/pulumi/registry/master/themes/default/data/registry/packages"

# createCommitOnBranch needs the repository's name-with-owner in its input.
repo_slug=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || exit 1

failures=()
updates=()
manual=()

# Extracts the first `<attr> = "<value>";` assignment from a nix file.
pin() { sed -n 's/^[[:space:]]*'"$1"' = "\(.*\)";/\1/p' "$2" | head -n1; }

# Latest release tag of a GitHub <owner>/<repo>, without the leading v.
latest_release() { gh api "repos/$1/releases/latest" --jq '.tag_name' 2>/dev/null | sed 's/^v//'; }

skip() {
  echo "  skip: $1"
  failures+=("$name: $2")
}

# Records a failed bump and restores the work tree; uses attempt_bump's locals.
fail() {
  echo "  $1"
  failures+=("$name: $1 ($old_version -> $new_version)")
  git checkout -- "$package_nix" README.md
}

# Rewrites version/hash/vendorHash via nix-update, builds the result, and
# opens a PR on success (or discards the change and records a failure).
attempt_bump() {
  local name="$1" package_nix="$2" old_version="$3" new_version="$4" pr_body="$5"
  local branch="update-$name-$new_version"

  # A bump stays pending until a human merges it; don't push over its branch.
  if [[ $(gh pr list --head "$branch" --state open --json number --jq 'length') != "0" ]]; then
    echo "  PR already open for $branch, skipping"
    return
  fi

  # --flake: no default.nix here; --override-filename: `src` positions
  # resolve into pulumi2nix's store path, which nix-update rejects.
  nix-update --flake "$name" --version="$new_version" --override-filename "$package_nix" ||
    { fail "nix-update failed"; return; }

  nix build ".#$name" ||
    { fail "build failed, discarding change"; return; }

  # The README's package tables print the pinned versions; rewrite the
  # package's own row and commit the README only if that changed anything.
  sed -i -E "s#^\| \`$name\` \|[^|]*\|#| \`$name\` | $new_version |#" README.md
  local files=("$package_nix")
  git diff --quiet README.md || files+=(README.md)

  # Committed remotely via createCommitOnBranch rather than git push: API
  # commits are GitHub-signed, which the branch's signature rule requires.
  # The mutation needs an existing branch, so the ref is created first.
  local head_sha
  head_sha=$(git rev-parse HEAD)
  gh api "repos/{owner}/{repo}/git/refs" \
    -f ref="refs/heads/$branch" -f sha="$head_sha" >/dev/null ||
    { fail "branch create failed"; return; }

  # shellcheck disable=SC2016 # $input is a GraphQL variable, not a shell one
  local mutation='mutation($input: CreateCommitOnBranchInput!) { createCommitOnBranch(input: $input) { commit { oid } } }'
  local payload
  payload=$(
    for f in "${files[@]}"; do
      jq -n --arg path "$f" --arg contents "$(base64 -w0 "$f")" \
        '{path: $path, contents: $contents}'
    done | jq -s \
      --arg query "$mutation" \
      --arg repo "$repo_slug" \
      --arg branch "$branch" \
      --arg oid "$head_sha" \
      --arg message "$name: $old_version -> $new_version" \
      '{query: $query, variables: {input: {
          branch: {repositoryNameWithOwner: $repo, branchName: $branch},
          expectedHeadOid: $oid,
          message: {headline: $message},
          fileChanges: {additions: .}
        }}}'
  )

  delete_branch() { gh api -X DELETE "repos/{owner}/{repo}/git/refs/heads/$branch" >/dev/null; }

  gh api graphql --input - <<<"$payload" >/dev/null ||
    { delete_branch; fail "commit create failed"; return; }

  # The change now lives only on the remote branch; reset the work tree so
  # the next package starts from a clean checkout.
  git checkout -- "${files[@]}"

  gh pr create --title "$name: $old_version -> $new_version" --body "$pr_body" --head "$branch" ||
    { delete_branch; fail "gh pr create failed"; return; }

  # Queued behind main's required `build` check rather than merged outright.
  # A bump whose build breaks in CI stays open for a person to look at.
  gh pr merge --auto --squash "$branch" ||
    echo "  auto-merge could not be enabled, leaving the PR open"

  updates+=("$name: $old_version -> $new_version")
}

mapfile -t names < <(jq -r 'keys[]' "$allowlist")
for name in "${names[@]}"; do
  echo "== $name =="

  package_nix="pkgs/plugins/$name/package.nix"
  [[ -f "$package_nix" ]] ||
    { skip "$package_nix does not exist" "missing $package_nix"; continue; }

  # A provider that isn't in the Pulumi registry declares `"source": "github"`
  # and is diffed against its own releases instead, the same way §5a handles
  # language runtimes. Its `repo_url` supplies the coordinates.
  version_source=$(jq -r --arg n "$name" '.[$n].source // "registry"' "$allowlist")
  if [[ "$version_source" == "github" ]]; then
    slug=$(jq -r --arg n "$name" '.[$n].repo_url' "$allowlist")
    slug=${slug#https://github.com/}

    latest_version=$(latest_release "$slug")
    [[ -n "$latest_version" ]] ||
      { skip "failed to fetch latest release for $slug" "GitHub release fetch failed"; continue; }

    pr_body="Automated update from the $slug GitHub releases."
  else
    registry_yaml=$(curl -fsSL "$registry_base/$name.yaml") ||
      { skip "failed to fetch registry metadata" "registry fetch failed"; continue; }

    latest_version=$(printf '%s\n' "$registry_yaml" | sed -n 's/^version:[[:space:]]*v\{0,1\}//p' | head -n1)
    [[ -n "$latest_version" ]] ||
      { skip "could not parse version from registry metadata" "unparseable registry version"; continue; }

    pr_body="Automated update from the Pulumi registry."
  fi

  pinned_version=$(pin version "$package_nix")
  [[ -n "$pinned_version" ]] ||
    { skip "could not parse pinned version from $package_nix" "unparseable pinned version"; continue; }

  [[ "$latest_version" != "$pinned_version" ]] ||
    { echo "  up to date ($pinned_version)"; continue; }

  # Packages whose `rev` isn't derivable from `version` are reported, not
  # PR'd. `!= false` because jq's `// true` treats explicit false as absent.
  auto_update=$(jq -r --arg n "$name" '.[$n].autoUpdate != false' "$allowlist")
  if [[ "$auto_update" != "true" ]]; then
    echo "  needs manual bump ($pinned_version -> $latest_version)"
    manual+=("$name: $pinned_version -> $latest_version")
    continue
  fi

  echo "  $pinned_version -> $latest_version"
  attempt_bump "$name" "$package_nix" "$pinned_version" "$latest_version" "$pr_body"
done

echo
echo "== language runtimes =="
for dir in pkgs/languages/pulumi-*/; do
  name=$(basename "$dir")
  echo "== $name =="

  package_nix="${dir}package.nix"
  pinned_version=$(pin version "$package_nix")
  if [[ -z "$pinned_version" ]]; then
    echo "  skip: re-export, no local pin"
    continue
  fi

  # An unstable-<date> pin tracks a commit on a source with no releases;
  # picking a new commit is a person's call.
  if [[ "$pinned_version" == unstable-* ]]; then
    echo "  skip: unstable pin, upstream has no releases ($pinned_version)"
    continue
  fi

  # Community hosts aren't under the pulumi org, so take the coordinates
  # from the package's own fetchFromGitHub instead of assuming pulumi/<name>.
  owner=$(pin owner "$package_nix")
  repo=$(pin repo "$package_nix")
  slug="${owner:-pulumi}/${repo:-$name}"

  latest_version=$(latest_release "$slug")
  [[ -n "$latest_version" ]] ||
    { skip "failed to fetch latest release for $slug" "GitHub release fetch failed"; continue; }

  [[ "$latest_version" != "$pinned_version" ]] ||
    { echo "  up to date ($pinned_version)"; continue; }

  # A package with two source hashes (pulumi-gestalt: vendorHash + cargoHash)
  # is beyond nix-update; its bump fails here rather than half-updating a PR.
  echo "  $pinned_version -> $latest_version"
  attempt_bump "$name" "$package_nix" "$pinned_version" "$latest_version" \
    "Automated update from the $slug GitHub releases."
done

# Prints "<label>: <count>" followed by one indented line per entry.
report() {
  local label="$1"
  shift
  echo "$label: $#"
  (($# == 0)) || printf '  %s\n' "$@"
}

# Same, as a markdown section for the workflow run's summary page.
report_md() {
  local label="$1"
  shift
  printf '### %s (%s)\n\n' "$label" "$#"
  if (($# > 0)); then
    printf -- '- %s\n' "$@"
  else
    echo "_none_"
  fi
  echo
}

echo
echo "== summary =="
report updated "${updates[@]}"
report "manual bumps needed" "${manual[@]}"
report failed "${failures[@]}"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## Update automation"
    echo
    report_md "Updated" "${updates[@]}"
    report_md "Manual bumps needed" "${manual[@]}"
    report_md "Failed" "${failures[@]}"
  } >>"$GITHUB_STEP_SUMMARY"
fi

if ((${#failures[@]} > 0)); then
  exit 1
fi
