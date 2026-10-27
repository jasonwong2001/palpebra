#!/bin/zsh
# Packages a clean checkout. Only --snapshot permits an untagged HEAD.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() {
    print -u2 -- "release: $*"
    exit 1
}

usage() {
    print -- "Usage: ./scripts/release.sh [--snapshot]"
    print -- "Default: clean checkout tagged v<VERSION>; --snapshot: clean checkout without a tag requirement."
}

(( $# <= 1 )) || fail "Expected no arguments or --snapshot. Use --help for usage."
snapshot=false
case "${1:-}" in
    --snapshot) snapshot=true ;;
    --help) usage; exit 0 ;;
    "") ;;
    *) fail "Unknown argument '$1'. Use --help for usage." ;;
esac

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "A git checkout is required."
head="$(git rev-parse --verify HEAD)" || fail "The checkout has no commits."
[[ -z "$(git status --porcelain --untracked-files=all)" ]] \
    || fail "Working tree is dirty. Commit or stash changes before packaging."
[[ -f VERSION ]] || fail "VERSION is missing."
version="$(< VERSION)"
[[ "$version" =~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' ]] \
    || fail "VERSION must contain a numeric major.minor.patch version."

if [[ "$snapshot" == true ]]; then
    short_sha="$(git rev-parse --short HEAD)"
    archive="Palpebra-${version}-snapshot-${short_sha}.zip"
else
    tag="v${version}"
    tagged_commit="$(git rev-parse --verify "refs/tags/${tag}^{commit}" 2>/dev/null)" \
        || fail "HEAD must be tagged $tag (from VERSION). Use --snapshot for an untagged build."
    [[ "$tagged_commit" == "$head" ]] \
        || fail "Tag $tag does not point to HEAD. Use --snapshot for an untagged build."
    archive="Palpebra-${version}.zip"
fi

# Release archives always use the universal release configuration, even if CONFIG was set by the caller.
CONFIG=release ./scripts/make-app.sh
[[ "$head" == "$(git rev-parse --verify HEAD)" && -z "$(git status --porcelain --untracked-files=all)" ]] \
    || fail "The checkout changed while building; no archive was written."

mkdir -p dist
staging="$(mktemp -d dist/.release-XXXXXX)"
trap 'rm -rf "$staging"' EXIT
trap 'exit 1' HUP INT TERM
ditto -c -k --keepParent build/Palpebra.app "$staging/$archive"
(
    cd "$staging"
    shasum -a 256 "$archive" > SHA256SUMS
    shasum -a 256 -c SHA256SUMS
)
mv "$staging/$archive" "dist/$archive"
mv "$staging/SHA256SUMS" dist/SHA256SUMS
print -- "Created dist/$archive and dist/SHA256SUMS"
