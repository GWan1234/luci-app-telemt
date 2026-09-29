#!/bin/sh
# Attach the matching telemt core packages to this repository's release.
#
#   tools/bundle-core.sh [TAG]          dry run: select, download, verify
#   UPLOAD=1 tools/bundle-core.sh TAG   ... and upload to release TAG of this repository
#
# TAG defaults to $GITHUB_REF_NAME. For release X.Y.Z (or X.Y.Z-N) the core release with
# the same base version is used: the highest revision among the tags X.Y.Z, X.Y.Z-2, ...
# of $CORE_REPO. Prereleases count, drafts do not.
#
# The core files are uploaded byte for byte, with the author's own signatures. They are
# NOT run through this repository's owfeed release, which would sign them with this
# repository's key and list them in this repository's manifest.txt: a package's
# signature has to be the key of the repository that built it. The core manifest is
# attached as core-manifest.txt(+.sig) so it cannot replace manifest.txt.
#
# No matching core release is not an error: the core is released first, and a luci
# release that runs earlier simply carries no bundle.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE_REPO="${CORE_REPO:-Medvedolog/telemt_owrt}"
CORE_KEY="$ROOT/keys/telemt-core-release.pub"
CORE_KEY_ID="d891db4d37ac55b2"
TARGET="${1:-${GITHUB_REF_NAME:-}}"
[ -n "$TARGET" ] || { echo "usage: tools/bundle-core.sh TAG" >&2; exit 1; }

VER="${TARGET#v}"
case "$VER" in
    [0-9]*.[0-9]*.[0-9]*-r[0-9]*) BASE="${VER%-r*}" ;;
    [0-9]*.[0-9]*.[0-9]*-[0-9]*)  BASE="${VER%-*}" ;;
    [0-9]*.[0-9]*.[0-9]*)         BASE="$VER" ;;
    *) echo "cannot derive a base version from tag: $TARGET" >&2; exit 1 ;;
esac

get() {
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        curl -fsSL --proto '=https' --tlsv1.2 --retry 5 --retry-delay 2 --retry-all-errors \
            -H "Authorization: Bearer $GITHUB_TOKEN" -o "$2" "$1"
    else
        curl -fsSL --proto '=https' --tlsv1.2 --retry 5 --retry-delay 2 --retry-all-errors -o "$2" "$1"
    fi
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Highest revision of the core release with this base version.
get "https://api.github.com/repos/$CORE_REPO/releases?per_page=100" "$work/releases.json"
CORE_TAG="$(jq -r --arg b "$BASE" '
    [ .[] | select(.draft | not) | .tag_name
      | select(. == $b or test("^" + ($b | gsub("\\."; "\\.")) + "-[0-9]+$")) ]
    | map({t: ., r: (if . == $b then 1 else (split("-") | last | tonumber) end)})
    | sort_by(.r) | last | .t // empty' "$work/releases.json")"

if [ -z "$CORE_TAG" ]; then
    echo "no $CORE_REPO release for base version $BASE yet; nothing to bundle"
    [ -z "${GITHUB_ACTIONS:-}" ] || echo "::notice::No $CORE_REPO release for $BASE yet; release $TARGET carries no core bundle"
    exit 0
fi
echo "core release: $CORE_REPO $CORE_TAG (for $TARGET)"
base="https://github.com/$CORE_REPO/releases/download/$CORE_TAG"

mkdir -p "$work/out"
get "$base/manifest.txt"     "$work/manifest.txt"
get "$base/manifest.txt.sig" "$work/manifest.txt.sig"

# Verify before reading: every value below steers a download.
owfeed verify-artifact --key "$CORE_KEY" --key-id "$CORE_KEY_ID" \
    --signature "$work/manifest.txt.sig" "$work/manifest.txt"

[ "$(head -n1 "$work/manifest.txt")" = "owfeed-manifest 1" ] || { echo "unexpected manifest format" >&2; exit 1; }
[ "$(awk '$1=="repo"{print $2; exit}' "$work/manifest.txt")" = "$CORE_REPO" ] || { echo "manifest is for another repository" >&2; exit 1; }
[ "$(awk '$1=="tag"{print $2; exit}' "$work/manifest.txt")" = "$CORE_TAG" ] || { echo "manifest is for another tag" >&2; exit 1; }
[ "$(awk '$1=="pkg"' "$work/manifest.txt" | wc -l)" -gt 0 ] || { echo "manifest names no packages" >&2; exit 1; }
[ -z "$(awk '$1=="pkg" && NF!=7 {print NR; exit}' "$work/manifest.txt")" ] || { echo "malformed manifest line" >&2; exit 1; }

# pkg <name> <format> <file> <size> <sha256> <arch>
awk '$1=="pkg"{print $4, $5, $6}' "$work/manifest.txt" | while read -r file size sum; do
    get "$base/$file" "$work/out/$file"
    [ "$(wc -c < "$work/out/$file" | tr -d ' ')" = "$size" ] || { echo "$file: size differs from the manifest" >&2; exit 1; }
    [ "$(sha256sum "$work/out/$file" | cut -d' ' -f1)" = "$sum" ] || { echo "$file: sha256 differs from the manifest" >&2; exit 1; }
    get "$base/$file.sig" "$work/out/$file.sig"
    echo "verified $file"
done

cp "$work/manifest.txt"     "$work/out/core-manifest.txt"
cp "$work/manifest.txt.sig" "$work/out/core-manifest.txt.sig"

count="$(ls "$work/out" | wc -l | tr -d ' ')"
echo "prepared $count core files from $CORE_TAG"

if [ "${UPLOAD:-0}" = "1" ]; then
    gh release upload "$TARGET" "$work/out"/* --clobber ${GITHUB_REPOSITORY:+-R "$GITHUB_REPOSITORY"}
    echo "uploaded to release $TARGET"
else
    echo "dry run (set UPLOAD=1 to upload)"
    ls "$work/out"
fi
