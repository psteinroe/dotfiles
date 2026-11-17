#!/usr/bin/env bash
# Offline fixtures for scripts/cliproxy-bump.sh: stubbed gh and prefetch, a temporary
# release.json, no network. Needs jq and nix (for `nix hash convert`).
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
script=$repo/scripts/cliproxy-bump.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

nix=$(command -v nix)
mkdir "$tmp/bin"
cat >"$tmp/bin/gh" <<EOF
#!/bin/sh
cat "$tmp/releases.json"
EOF
cat >"$tmp/bin/nix" <<EOF
#!/bin/sh
if [ "\$1 \$2" = "store prefetch-file" ]; then
  echo "\$@" >>"$tmp/prefetched"
  printf '{"hash":"%s"}\n' "\$(cat "$tmp/prefetch-hash")"
else
  exec "$nix" "\$@"
fi
EOF
chmod +x "$tmp/bin/gh" "$tmp/bin/nix"
export PATH="$tmp/bin:$PATH"
export CLIPROXY_RELEASE_FILE=$tmp/release.json
# 2026-11-17T00:00:00Z
export CLIPROXY_NOW=1794873600

hex=81696a2a14a1c3e2cb27bb338c94fadad3e85c5f1180e502ccf3fa99e905d4ac
sri=$("$nix" hash convert --hash-algo sha256 --to sri "$hex")
printf '%s' "$sri" >"$tmp/prefetch-hash"

release() { # version published_at [draft] [prerelease] [asset arch]
  jq -n --arg v "$1" --arg at "$2" --argjson draft "${3:-false}" --argjson pre "${4:-false}" \
    --arg arch "${5:-aarch64}" --arg digest "sha256:$hex" '{
      tag_name: "v\($v)", published_at: $at, draft: $draft, prerelease: $pre,
      assets: [{name: "CLIProxyAPI_\($v)_linux_\($arch)_no-plugin.tar.gz", digest: $digest}]}'
}
releases() { jq -s . >"$tmp/releases.json"; }
current() { printf '{"version":"%s","hash":"sha256-old"}\n' "$1" >"$tmp/release.json"; }

# Picks the highest version that is old enough, skipping drafts, prereleases and
# releases without the aarch64 build, and compares versions numerically.
{
  release 8.0.76 2026-11-16T00:00:00Z
  release 8.0.71 2026-11-09T00:00:00Z true
  release 8.0.70 2026-11-09T00:00:00Z false true
  release 8.0.69 2026-11-09T00:00:00Z false false x86_64
  release 8.0.68 2026-11-09T23:00:00Z
  release 8.0.9 2026-09-01T00:00:00Z
} | releases
current 8.0.44
out=$(bash "$script" 2>/dev/null)
[ "$out" = 8.0.68 ] || fail "picked '$out', want 8.0.68"
[ "$(jq -r .version "$tmp/release.json")" = 8.0.68 ] || fail "version not written"
[ "$(jq -r .hash "$tmp/release.json")" = "$sri" ] || fail "hash not written"
grep -q 'download/v8.0.68/CLIProxyAPI_8.0.68_linux_aarch64_no-plugin.tar.gz' "$tmp/prefetched" ||
  fail "prefetched the wrong URL"

# The age limit is an argument.
current 8.0.44
out=$(bash "$script" 0 2>/dev/null)
[ "$out" = 8.0.76 ] || fail "picked '$out' with no age limit, want 8.0.76"

# Already current, or ahead of what is old enough: nothing changes, nothing is fetched.
for version in 8.0.68 8.0.76; do
  current "$version"
  rm -f "$tmp/prefetched"
  cp "$tmp/release.json" "$tmp/before"
  out=$(bash "$script" 2>/dev/null)
  [ -z "$out" ] || fail "bumped $version to '$out'"
  cmp -s "$tmp/release.json" "$tmp/before" || fail "rewrote release.json on $version"
  [ ! -e "$tmp/prefetched" ] || fail "prefetched on $version"
done

# A download that doesn't match GitHub's digest leaves release.json alone.
current 8.0.44
cp "$tmp/release.json" "$tmp/before"
"$nix" hash convert --hash-algo sha256 --to sri "${hex%?}0" | tr -d '\n' >"$tmp/prefetch-hash"
if bash "$script" >/dev/null 2>"$tmp/err"; then fail "accepted a digest mismatch"; fi
grep -q 'GitHub lists' "$tmp/err" || fail "unexpected error: $(cat "$tmp/err")"
cmp -s "$tmp/release.json" "$tmp/before" || fail "rewrote release.json on a digest mismatch"

echo "cliproxy-bump: ok"
