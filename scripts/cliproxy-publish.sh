#!/usr/bin/env bash
# Publishes a built cliproxy Pi system as the cliproxy-pi release of this repo, which the
# Pi polls (nix/nixos/cliproxy/deploy.nix). Paths cache.nixos.org already serves stay
# there; the rest go into a signed binary cache, uploaded as cache-<hash>.tar. The
# `system` asset, uploaded last, names the store path to switch to. Runs in CI with
# GH_TOKEN and the signing key in CLIPROXY_SIGNING_KEY.
#
#   scripts/cliproxy-publish.sh SYSTEM
set -euo pipefail
system=$(readlink -f "$1")
tag=cliproxy-pi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

(umask 077 && printf '%s\n' "$CLIPROXY_SIGNING_KEY" >"$work/key")

# A binary cache only accepts paths whose references it holds, so copy the whole
# closure, then drop what cache.nixos.org serves; the Pi substitutes that from there.
nix copy --to "file://$work/cache?compression=zstd&secret-key=$work/key" "$system"
nix path-info --recursive "$system" >"$work/closure"
# shellcheck disable=SC2016 # expanded by the inner sh
xargs -P 32 -n 1 sh -c '
  h=${1#/nix/store/}
  if curl -fsI -o /dev/null "https://cache.nixos.org/${h%%-*}.narinfo"; then echo "${h%%-*}"; fi
' sh <"$work/closure" >"$work/upstream"
while read -r h; do
  nar=$(sed -n 's/^URL: //p' "$work/cache/$h.narinfo")
  rm -f "$work/cache/$h.narinfo" "$work/cache/$nar"
done <"$work/upstream"
echo "$(($(wc -l <"$work/closure") - $(wc -l <"$work/upstream"))) of $(wc -l <"$work/closure") paths are not on cache.nixos.org"
h=${system#/nix/store/}
cache=cache-${h%%-*}.tar
tar -cf "$work/$cache" -C "$work/cache" .
du -h "$work/$cache"
printf '%s\n' "$system" >"$work/system"

if ! gh release view "$tag" >/dev/null 2>&1; then
  gh release create "$tag" --prerelease --latest=false --title "cliproxy Pi system" \
    --notes "Built by .github/workflows/cliproxy-deploy.yml from main. The cliproxy Pi polls this release and switches to the system it names."
fi
gh release upload "$tag" "$work/$cache" --clobber
gh release upload "$tag" "$work/system" --clobber
gh release view "$tag" --json assets --jq '.assets[].name' |
  { grep -E '^cache-.*\.tar$' || true; } | { grep -vxF "$cache" || true; } |
  xargs -r -n 1 gh release delete-asset "$tag" -y
echo "Published $system"
