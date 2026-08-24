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

# createCommitOnBranch needs the repository's name-with-owner in its input;
# resolve it once from the checkout's remote rather than hardcoding it.
repo_slug=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || exit 1

failures=()
updates=()
manual=()

# Rewrites version/hash/vendorHash via nix-update, builds the result, and
# opens a PR on success (or discards the change and records a failure).
attempt_bump() {
  local name="$1" package_nix="$2" old_version="$3" new_version="$4" attr="$5" pr_body="$6"
  local branch="update-$name-$new_version"

  # A bump stays pending until a human merges it, so every run in between
  # would otherwise rebuild it and then fail to push over the existing
  # remote branch.
  local open_prs
  open_prs=$(gh pr list --head "$branch" --state open --json number --jq 'length')
  if [[ "$open_prs" != "0" ]]; then
    echo "  PR already open for $branch, skipping"
    return
  fi

  # nix-update needs --flake (this repo has no default.nix) and
  # --override-filename: the packages' `src` position resolves into
  # pulumi2nix's store path, not into this repo, so the default position
  # sanitizer rejects it.
  if ! nix-update --flake "$attr" \
    --version="$new_version" \
    --override-filename "$package_nix"; then
    echo "  nix-update failed"
    git checkout -- "$package_nix"
    failures+=("$name: nix-update failed ($old_version -> $new_version)")
    return
  fi

  if ! nix build ".#$attr"; then
    echo "  build failed, discarding change"
    git checkout -- "$package_nix"
    failures+=("$name: build failed ($old_version -> $new_version)")
    return
  fi

  # The README's package tables print the pinned versions, so a bump that
  # doesn't touch them publishes a stale table. Only the version cell of the
  # package's own row is rewritten, and only if that row exists, so a package
  # the README doesn't list is skipped rather than silently mismatched.
  local readme_files=()
  if grep -qE "^\| \`$name\` \|" README.md; then
    sed -i -E "s#^\| \`$name\` \|[^|]*\|#| \`$name\` | $new_version |#" README.md
    readme_files=(README.md)
  fi

  # The commit is created remotely with createCommitOnBranch instead of
  # git commit + push: API commits are signed by GitHub, which the target
  # branch's "verified signatures" rule requires, and CI's token has no
  # signing key of its own. The mutation can only target a branch that
  # already exists, so the ref is created first, at the current HEAD.
  local head_sha
  head_sha=$(git rev-parse HEAD)
  if ! gh api "repos/{owner}/{repo}/git/refs" \
    -f ref="refs/heads/$branch" -f sha="$head_sha" >/dev/null; then
    echo "  branch create failed"
    git checkout -- "$package_nix" "${readme_files[@]}"
    failures+=("$name: branch create failed ($old_version -> $new_version)")
    return
  fi

  # shellcheck disable=SC2016 # $input is a GraphQL variable, not a shell one
  local mutation='mutation($input: CreateCommitOnBranchInput!) { createCommitOnBranch(input: $input) { commit { oid } } }'
  local payload
  payload=$(
    for f in "$package_nix" "${readme_files[@]}"; do
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

  if ! gh api graphql --input - <<<"$payload" >/dev/null; then
    echo "  commit create failed"
    gh api -X DELETE "repos/{owner}/{repo}/git/refs/heads/$branch" >/dev/null
    git checkout -- "$package_nix" "${readme_files[@]}"
    failures+=("$name: commit create failed ($old_version -> $new_version)")
    return
  fi

  # The change now lives only on the remote branch; reset the work tree so
  # the next package starts from a clean checkout.
  git checkout -- "$package_nix" "${readme_files[@]}"

  if ! gh pr create \
    --title "$name: $old_version -> $new_version" \
    --body "$pr_body" \
    --head "$branch"; then
    echo "  gh pr create failed"
    gh api -X DELETE "repos/{owner}/{repo}/git/refs/heads/$branch" >/dev/null
    failures+=("$name: gh pr create failed ($old_version -> $new_version)")
    return
  fi

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

  # Packages whose `rev` isn't derivable from `version` can't be bumped by
  # rewriting the version string alone; they're reported, not PR'd.
  # `!= false` rather than `// true`: jq's alternative operator treats an
  # explicit `false` as absent, so `.autoUpdate // true` is always true.
  auto_update=$(jq -r --arg n "$name" '.[$n].autoUpdate != false' "$allowlist")
  if [[ "$auto_update" != "true" ]]; then
    echo "  needs manual bump ($pinned_version -> $registry_version)"
    manual+=("$name: $pinned_version -> $registry_version")
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

  # An unstable-<date> pin names a commit on a source that has no releases,
  # so there is no upstream version to compare it against. Bumping it means
  # picking a new commit, which is a person's call.
  if [[ "$pinned_version" == unstable-* ]]; then
    echo "  skip: unstable pin, upstream has no releases ($pinned_version)"
    continue
  fi

  # Community language hosts are not under the pulumi org and are not always
  # named after the package, so take the coordinates from the package's own
  # fetchFromGitHub instead of assuming pulumi/<name>.
  owner=$(sed -n 's/^[[:space:]]*owner = "\(.*\)";/\1/p' "$package_nix" | head -n1)
  repo=$(sed -n 's/^[[:space:]]*repo = "\(.*\)";/\1/p' "$package_nix" | head -n1)
  slug="${owner:-pulumi}/${repo:-$name}"

  latest_version=$(gh api "repos/$slug/releases/latest" --jq '.tag_name' 2>/dev/null | sed 's/^v//')
  if [[ -z "$latest_version" ]]; then
    echo "  skip: failed to fetch latest release for $slug"
    failures+=("$name: GitHub release fetch failed")
    continue
  fi

  if [[ "$latest_version" == "$pinned_version" ]]; then
    echo "  up to date ($pinned_version)"
    continue
  fi

  # A package built from more than one source hash (pulumi-gestalt pins both
  # a vendorHash and a cargoHash) is beyond what nix-update rewrites in one
  # pass; such a bump will fail here and land in the failures list rather
  # than producing a half-updated PR.
  echo "  $pinned_version -> $latest_version"
  attempt_bump "$name" "$package_nix" "$pinned_version" "$latest_version" "$name" \
    "Automated update from the $slug GitHub releases."
done

# Prints "<label>: <count>" followed by one indented line per entry, with no
# stray blank line when the list is empty.
report() {
  local label="$1"
  shift
  echo "$label: $#"
  if (($# > 0)); then
    printf '  %s\n' "$@"
  fi
}

# Same, as a markdown section for the workflow run's summary page.
report_md() {
  local label="$1"
  shift
  echo "### $label ($#)"
  echo
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
