#!/usr/bin/env bash
# Moves the cliproxy Pi to the newest CLIProxyAPI release that has been out for at least
# MIN_AGE_DAYS (default 3), so a broken release has had time to be noticed and replaced
# upstream. Never moves backwards. Prints the new version when it changed, nothing
# otherwise. Needs gh, jq and nix.
#
#   scripts/cliproxy-bump.sh [MIN_AGE_DAYS]
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
file=${CLIPROXY_RELEASE_FILE:-$repo/nix/nixos/cliproxy/release.json}
min_age_days=${1:-3}
now=${CLIPROXY_NOW:-$(date -u +%s)}
upstream=router-for-me/CLIProxyAPI

current=$(jq -er .version "$file")

# The last 100 releases cover months at upstream's pace. One line per release old
# enough that ships the static aarch64 build: version and the asset's digest.
candidates=$(gh api "repos/$upstream/releases?per_page=100" | jq -r \
  --argjson cutoff "$((now - min_age_days * 86400))" '
  .[]
  | select((.draft | not) and (.prerelease | not))
  | select((.published_at | fromdateiso8601) <= $cutoff)
  | (.tag_name | ltrimstr("v")) as $v
  | (.assets[] | select(.name == "CLIProxyAPI_\($v)_linux_aarch64_no-plugin.tar.gz")) as $a
  | "\($v) \($a.digest // "")"')

if [ -z "$candidates" ]; then
  echo "No CLIProxyAPI release is at least $min_age_days days old" >&2
  exit 0
fi

read -r version digest < <(sort -V -k1,1 <<<"$candidates" | tail -n1)
if [ "$(printf '%s\n%s\n' "$current" "$version" | sort -V | tail -n1)" = "$current" ]; then
  echo "CLIProxyAPI $current is current (newest release at least $min_age_days days old: $version)" >&2
  exit 0
fi

url="https://github.com/$upstream/releases/download/v$version/CLIProxyAPI_${version}_linux_aarch64_no-plugin.tar.gz"
hash=$(nix store prefetch-file --json --hash-type sha256 "$url" | jq -er .hash)
# GitHub records a digest per uploaded asset; a mismatch means the download changed
if [ -n "$digest" ]; then
  hex=$(nix hash convert --hash-algo sha256 --to base16 "$hash")
  if [ "sha256:$hex" != "$digest" ]; then
    echo "Downloaded CLIProxyAPI $version is sha256:$hex, GitHub lists $digest" >&2
    exit 1
  fi
fi

jq -n --arg version "$version" --arg hash "$hash" '{version: $version, hash: $hash}' >"$file.tmp"
mv "$file.tmp" "$file"
echo "CLIProxyAPI $current -> $version" >&2
echo "$version"
