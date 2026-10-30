#!/usr/bin/env bash
# Offline fixtures only: no network, Nix installation, service or browser is used.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
real_git=$(command -v git)
export TEST_GIT=$real_git
passed=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
contains() { grep -Fq -- "$2" "$1" || fail "$1 lacks: $2"; }
not_contains() { ! grep -Fq -- "$2" "$1" || fail "$1 contains: $2"; }
expect_failure() { if "$@" >"$case_root/out" 2>"$case_root/err"; then fail "Unexpected success: $*"; fi; }
mock() { { printf '#!/bin/bash\nset -euo pipefail\n'; printf '%s\n' "$2"; } >"$mock_bin/$1"; chmod +x "$mock_bin/$1"; }

auth_fixture() {
  export TEST_LOG=$case_root/ssh TEST_BROWSER_LOG=$case_root/browser TEST_PAYLOAD=$case_root/payload
  export TMPDIR=$case_root/tmp TEST_AUTH_URL='' TEST_AUTH_STATUS=0 TEST_FORWARD_FAIL=0 TEST_AUTH_WAIT=0
  mkdir -p "$case_root/tmp" "$case_root/bin"
  : >"$TEST_LOG"; : >"$TEST_BROWSER_LOG"
  mock_bin=$case_root/bin
  mock ssh '
printf "%s\n" "$*" >>"$TEST_LOG"
case $1 in
  -tt)
    printf "%s\n" "$$" >"$TMPDIR/ssh-pid"
    printf "%s\n" "$TEST_AUTH_URL"
    if [[ $TEST_AUTH_WAIT == 1 ]]; then exec /bin/cat "$TMPDIR/block"; fi
    exit "$TEST_AUTH_STATUS" ;;
  -fNT)
    if [[ -p $TMPDIR/ready ]]; then printf "ready\n" >"$TMPDIR/ready"; fi
    exit "$TEST_FORWARD_FAIL" ;;
  -S) exit 0 ;;
  *) /bin/cat >"$TEST_PAYLOAD" ;;
esac'
  mock uname 'printf "Darwin\n"'
  mock open 'printf "%s\n" "$*" >>"$TEST_BROWSER_LOG"'
  export PATH=$mock_bin:$PATH
}

test_missing_host() { auth_fixture; expect_failure "$repo/bin/remote" deploy; [[ ! -s $TEST_LOG ]]; }
test_bad_hosts() {
  auth_fixture
  local host
  for host in '-oProxyCommand=bad' 'host;bad' 'user@host bad'; do expect_failure "$repo/bin/remote" status "$host"; done
  [[ ! -s $TEST_LOG ]]
}
test_payload() {
  auth_fixture
  "$repo/bin/remote" deploy user@box --ref feature/t3 --force
  contains "$TEST_LOG" 'user@box bash -s -- deploy feature/t3 1 0'
  cmp "$TEST_PAYLOAD" "$repo/scripts/remote-host.sh"
}
test_setup_modes() {
  auth_fixture
  "$repo/bin/remote" setup user@box --home-manager --allow-t3-update
  contains "$TEST_LOG" 'setup'
  contains "$TEST_LOG" '0 1'
  "$repo/bin/remote" setup user@box --nixos-flake /etc/nixos#box
  contains "$TEST_LOG" '/etc/nixos'
  : >"$TEST_LOG"
  expect_failure "$repo/bin/remote" setup user@box --home-manager --nixos-flake /etc/nixos#box
  expect_failure "$repo/bin/remote" setup user@box --nixos-flake /etc/nixos#box --home-manager
  expect_failure "$repo/bin/remote" deploy user@box --ref 'main;bad'
  expect_failure "$repo/bin/remote" deploy user@box --ref
  expect_failure "$repo/bin/remote" setup user@box --nixos-flake
  expect_failure "$repo/bin/remote" status user@box --force
  [[ ! -s $TEST_LOG ]]
}
test_mcp_login() {
  auth_fixture
  export TEST_AUTH_URL='https://oauth.example.invalid/authorize?redirect_uri=http%3A%2F%2F127.0.0.1%3A54321%2Fcallback'
  "$repo/bin/remote" auth fixture-host mcp executor --client codex >"$case_root/out"
  contains "$TEST_LOG" 'codex mcp login executor --no-browser'
  contains "$TEST_LOG" '127.0.0.1:54321:127.0.0.1:54321'
  contains "$TEST_LOG" '-O exit fixture-host'
  contains "$TEST_BROWSER_LOG" "$TEST_AUTH_URL"
  ! compgen -G "$TMPDIR/remote-oauth.*" >/dev/null
}
test_bad_mcp() {
  auth_fixture
  expect_failure "$repo/bin/remote" auth fixture-host mcp --bad
  expect_failure "$repo/bin/remote" auth fixture-host mcp executor --client bad
  expect_failure "$repo/bin/remote" auth fixture-host mcp executor --client
  expect_failure "$repo/bin/remote" auth fixture-host mcp
  [[ ! -s $TEST_LOG ]]
}
test_github_login() {
  auth_fixture
  export TEST_AUTH_URL='https://github.com/login/device'
  "$repo/bin/remote" auth fixture-host gh >"$case_root/out"
  contains "$TEST_LOG" 'gh auth login --hostname github.com --git-protocol https --web'
  contains "$TEST_LOG" 'export GIT_CONFIG_GLOBAL='
  contains "$TEST_BROWSER_LOG" "$TEST_AUTH_URL"
  not_contains "$TEST_LOG" '-L '
  not_contains "$TEST_LOG" 'encoded='
}
test_callback_validation() {
  # Pure helpers can be sourced without dispatching a command.
  source "$repo/bin/remote"
  [[ $(_remote_callback_forward 'https://a.invalid/?redirect_uri=http%3A%2F%2Flocalhost%3A12345%2Fcb') == localhost:12345:localhost:12345 ]]
  [[ $(_remote_callback_forward 'https://a.invalid/?redirect_uri=http%3A%2F%2F%5B%3A%3A1%5D%3A12345%2Fcb') == '[::1]:12345:[::1]:12345' ]]
  local redirect
  for redirect in 'http://evil.invalid:12345/cb' 'http://localhost.evil:12345/cb' 'http://127.0.0.1:0/cb' 'http://127.0.0.1:99999/cb' '%00' '%zz'; do
    if _remote_callback_forward "https://a.invalid/?redirect_uri=$redirect"; then fail "Unsafe callback: $redirect"; fi
  done
}
test_native_failure_and_forward_fallback() {
  auth_fixture
  export TEST_AUTH_URL='https://oauth.example.invalid/?redirect_uri=http%3A%2F%2Flocalhost%3A54321%2Fcallback'
  export TEST_AUTH_STATUS=17
  if "$repo/bin/remote" auth fixture-host mcp executor >"$case_root/out" 2>"$case_root/err"; then fail 'Native failure hidden'; else [[ $? == 17 ]]; fi
  contains "$TEST_LOG" '-O exit fixture-host'
  ! compgen -G "$TMPDIR/remote-oauth.*" >/dev/null
  export TEST_AUTH_STATUS=0 TEST_FORWARD_FAIL=1
  "$repo/bin/remote" auth fixture-host mcp executor >"$case_root/out" 2>"$case_root/err"
  contains "$case_root/err" 'Callback forwarding unavailable'
  contains "$TEST_BROWSER_LOG" "$TEST_AUTH_URL"
  ! compgen -G "$TMPDIR/remote-oauth.*" >/dev/null
}
test_cancel_cleanup() {
  auth_fixture
  export TEST_AUTH_WAIT=1
  export TEST_AUTH_URL='https://oauth.example.invalid/?redirect_uri=http%3A%2F%2F127.0.0.1%3A54321%2Fcallback'
  mkfifo "$TMPDIR/block" "$TMPDIR/ready"
  exec 9<>"$TMPDIR/ready"
  "$repo/bin/remote" auth fixture-host mcp executor >"$case_root/out" 2>"$case_root/err" &
  local cli_pid=$! ready native_pid
  if ! IFS= read -r -t 5 ready <&9; then kill -TERM "$cli_pid"; wait "$cli_pid" || true; fail 'Login never reached forwarding'; fi
  native_pid=$(<"$TMPDIR/ssh-pid")
  kill -TERM "$cli_pid"
  if wait "$cli_pid"; then fail 'Cancellation returned success'; else [[ $? == 143 ]]; fi
  exec 9>&-
  contains "$TEST_LOG" '-O exit fixture-host'
  ! kill -0 "$native_pid" 2>/dev/null
  ! compgen -G "$TMPDIR/remote-oauth.*" >/dev/null
}

host_fixture() {
  export HOME=$case_root/home TEST_UPSTREAM=$case_root/upstream TEST_LOG=$case_root/commands
  mock_bin=$HOME/.local/bin
  checkout=$HOME/Developer/dotfiles
  state=$HOME/.config/dotfiles
  mkdir -p "$mock_bin" "$state/flake"
  : >"$TEST_LOG"
  "$real_git" init -q -b main "$TEST_UPSTREAM"
  "$real_git" -C "$TEST_UPSTREAM" config user.name Fixture
  "$real_git" -C "$TEST_UPSTREAM" config user.email fixture@example.invalid
  "$real_git" -C "$TEST_UPSTREAM" config commit.gpgsign false
  printf 'original\n' >"$TEST_UPSTREAM/settings.json"
  "$real_git" -C "$TEST_UPSTREAM" add .
  "$real_git" -C "$TEST_UPSTREAM" commit -qm initial
  "$real_git" clone -q "$TEST_UPSTREAM" "$checkout"
  printf 'mode=home-manager\ntarget=%q/flake#remote\nREMOTE_REF=main\nDEPLOYED_T3_VERSION=0.1.0\n' "$state" >"$state/remote.env"
  mock uname 'if [[ ${1:-} == -m ]]; then echo x86_64; else echo Linux; fi'
  mock id 'if [[ $1 == -u ]]; then echo 1000; else echo fixture; fi'
  mock git '
if [[ $* == *"remote get-url origin"* ]]; then
  echo https://github.com/psteinroe/dotfiles.git
elif [[ $* == *"fetch origin"* ]]; then
  printf "fetch\n" >>"$TEST_LOG"
  exec "$TEST_GIT" -C "$2" fetch "$TEST_UPSTREAM" "${@: -1}"
else exec "$TEST_GIT" "$@"; fi'
  mock nix 'printf "nix %s\n" "$*" >>"$TEST_LOG"; if [[ $1 == eval ]]; then printf 0.1.0; fi'
  mock tailscale 'printf "%s\n" '\''{"BackendState":"Running"}'\'
  mock systemctl 'printf "systemctl %s\n" "$*" >>"$TEST_LOG"'
  mock sudo 'printf "sudo %s\n" "$*" >>"$TEST_LOG"'
  mock loginctl 'echo no'
  mock ssh 'echo "Unexpected SSH in host fixture" >&2; exit 99'
  export PATH=$mock_bin:$PATH
}
deploy() { bash "$repo/scripts/remote-host.sh" deploy '' "${1:-0}" 0 '' "${2:-0}" >"$case_root/out" 2>"$case_root/err"; }
advance_upstream() {
  printf 'new\n' >"$TEST_UPSTREAM/new-file"
  "$real_git" -C "$TEST_UPSTREAM" add .
  "$real_git" -C "$TEST_UPSTREAM" commit -qm advance
}
version_change() {
  printf 'mode=home-manager\ntarget=%q/flake#remote\nREMOTE_REF=main\nDEPLOYED_T3_VERSION=0.0.9\n' "$state" >"$state/remote.env"
}
test_dirty_checkout() {
  host_fixture
  printf 'UI settings\n' >"$checkout/settings.json"
  if deploy; then fail 'Dirty checkout applied'; fi
  contains "$case_root/err" 'Dirty dotfiles checkout'
  [[ ! -s $TEST_LOG && $(<"$checkout/settings.json") == 'UI settings' ]]
}
test_untracked_checkout() {
  host_fixture
  printf 'keep\n' >"$checkout/notes"
  if deploy; then fail 'Untracked file ignored'; fi
  [[ -f $checkout/notes && ! -s $TEST_LOG ]]
}
test_fast_forward() {
  host_fixture; advance_upstream; deploy
  [[ -f $checkout/new-file ]]
  contains "$TEST_LOG" 'home-manager -- switch'
  contains "$TEST_LOG" 'sudo -n loginctl enable-linger fixture'
  not_contains "$TEST_LOG" nixos-rebuild
}
test_no_sudo() {
  host_fixture
  mock loginctl 'echo yes'
  mock sudo 'echo "Unexpected sudo" >&2; exit 99'
  deploy
}
test_nixos_switch() {
  host_fixture
  printf 'mode=nixos\ntarget=%q/flake#remote\nREMOTE_REF=main\nDEPLOYED_T3_VERSION=0.1.0\n' "$state" >"$state/remote.env"
  mock nix 'printf "nix %s\n" "$*" >>"$TEST_LOG"; if [[ $1 == eval ]]; then if [[ $* == *config.dotfiles.remote.user* ]]; then printf fixture; else printf 0.1.0; fi; fi'
  deploy
  contains "$TEST_LOG" 'sudo -n env NIX_CONFIG='
  contains "$TEST_LOG" 'nixos-rebuild switch --impure --flake'
  not_contains "$TEST_LOG" 'home-manager -- switch'
}
test_host_owned_flake_locks_as_root() {
  host_fixture
  mkdir -p "$case_root/etc-nixos"
  chmod 555 "$case_root/etc-nixos"
  printf 'mode=nixos\ntarget=%q#box\nREMOTE_REF=main\nDEPLOYED_T3_VERSION=0.1.0\n' "$case_root/etc-nixos" >"$state/remote.env"
  mock nix 'printf "nix %s\n" "$*" >>"$TEST_LOG"; if [[ $1 == eval ]]; then if [[ $* == *config.dotfiles.remote.user* ]]; then printf fixture; else printf 0.1.0; fi; fi'
  deploy
  chmod 755 "$case_root/etc-nixos"
  # The lock runs through sudo; the user never writes the root-owned flake directly.
  [[ $(grep -c '^nix flake lock' "$TEST_LOG") == 0 ]]
  contains "$TEST_LOG" "nix flake lock --update-input dotfiles $case_root/etc-nixos"
  contains "$TEST_LOG" "nixos-rebuild switch --impure --flake $case_root/etc-nixos#box"
}
test_tailscale_enrollment() {
  host_fixture
  mock tailscale 'echo '\''{"BackendState":"NeedsLogin"}'\'
  if deploy; then fail 'Unenrolled Tailscale accepted'; fi
  contains "$case_root/err" 'sudo tailscale up'
  not_contains "$TEST_LOG" 'restart t3code'
}
test_force() {
  host_fixture
  printf 'discard\n' >"$checkout/settings.json"
  printf 'discard\n' >"$checkout/notes"
  advance_upstream; deploy 1
  [[ $(<"$checkout/settings.json") == original && ! -e $checkout/notes && -f $checkout/new-file ]]
}
test_divergence() {
  host_fixture
  "$real_git" -C "$checkout" config user.name Fixture
  "$real_git" -C "$checkout" config user.email fixture@example.invalid
  "$real_git" -C "$checkout" config commit.gpgsign false
  printf 'keep\n' >"$checkout/local"
  "$real_git" -C "$checkout" add .
  "$real_git" -C "$checkout" commit -qm local
  advance_upstream
  if deploy; then fail 'Diverged checkout applied'; fi
  not_contains "$TEST_LOG" 'nix run'
  [[ -f $checkout/local ]]
}
test_version_gate() {
  host_fixture; version_change
  if deploy; then fail 'Version change bypassed permission'; fi
  contains "$case_root/err" --allow-t3-update
  not_contains "$TEST_LOG" 'nix run'
}
test_version_backup() {
  host_fixture; version_change
  mkdir -p "$HOME/.t3"
  printf 'preserve\n' >"$HOME/.t3/state"
  deploy 0 1
  local -a backups=("$HOME"/.local/state/dotfiles/backups/t3-0.0.9-*/state)
  [[ ${#backups[@]} == 1 && $(<"${backups[0]}") == preserve ]]
  local stop_line switch_line
  stop_line=$(grep -n 'stop t3code' "$TEST_LOG" | head -1 | cut -d: -f1)
  switch_line=$(grep -n 'nix run' "$TEST_LOG" | head -1 | cut -d: -f1)
  [[ $stop_line -lt $switch_line ]]
}

for test in test_missing_host test_bad_hosts test_payload test_setup_modes test_mcp_login test_bad_mcp test_github_login test_callback_validation test_native_failure_and_forward_fallback test_cancel_cleanup test_dirty_checkout test_untracked_checkout test_fast_forward test_no_sudo test_nixos_switch test_host_owned_flake_locks_as_root test_tailscale_enrollment test_force test_divergence test_version_gate test_version_backup; do
  (
    case_root=$fixture/$test
    mkdir -p "$case_root"
    "$test"
  )
  printf 'PASS %s\n' "$test"
  passed=$((passed + 1))
done
printf '%s remote CLI/host fixtures passed\n' "$passed"
