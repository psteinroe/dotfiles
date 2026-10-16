#!/usr/bin/env zsh
set -euo pipefail

repo_root=${0:A:h:h:h}
test_root=$(mktemp -d)
trap 'if [[ "${KEEP_WTCLEAN_FIXTURE:-0}" == 1 ]]; then print -u2 -- "kept fixture: $test_root"; else rm -rf "$test_root"; fi' EXIT

failures=0
fail() {
  print -u2 -- "wtclean test failed: $*"
  failures=$((failures + 1))
  return 0
}

make_fixture() {
  local fixture="$1"
  mkdir -p "$fixture/seed" "$fixture/bin" "$fixture/home/.local" "$fixture/session"
  # Shared helpers prepend ~/.local/bin: keep every executable stub first.
  ln -s "$fixture/bin" "$fixture/home/.local/bin"
  git -C "$fixture/seed" init -q
  git -C "$fixture/seed" config user.name Test
  git -C "$fixture/seed" config user.email test@example.com
  print -r -- base > "$fixture/seed/file"
  git -C "$fixture/seed" add file
  git -C "$fixture/seed" commit -qm base
  git -C "$fixture/seed" branch -M main
  git -C "$fixture/seed" branch merged-a
  git -C "$fixture/seed" branch merged-b

  git init --bare -q "$fixture/repo.git"
  git -C "$fixture/seed" remote add origin "$fixture/repo.git"
  git -C "$fixture/seed" push -q origin main merged-a merged-b
  git --git-dir="$fixture/repo.git" symbolic-ref HEAD refs/heads/main
  git --git-dir="$fixture/repo.git" worktree add -q "$fixture/repo.git/main" main
  git --git-dir="$fixture/repo.git" worktree add -q "$fixture/repo.git/a" merged-a
  git --git-dir="$fixture/repo.git" worktree add -q "$fixture/repo.git/b" merged-b

  cat > "$fixture/bin/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "repo view") printf 'main\n' ;;
  "pr view") printf 'MERGED\n' ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$fixture/bin/gh"

  cat > "$fixture/bin/herdr" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HERDR_TRACE"
case "$1 $2" in
  "workspace list") printf '{"result":{"workspaces":[]}}\n' ;;
  "workspace get")
    if grep -Fqx "workspace close $3" "$HERDR_TRACE"; then
      exit 1
    fi
    printf '{"result":{}}\n'
    ;;
  "pane list")
    case "$4" in
      ws-idle)
        printf '{"result":{"panes":[{"agent":"pi","agent_status":"idle","agent_session":{"agent":"pi"}}]}}\n'
        ;;
      ws-done)
        printf '{"result":{"panes":[{"agent":"pi","agent_status":"done","agent_session":{"agent":"pi"}}]}}\n'
        ;;
      ws-working)
        printf '{"result":{"panes":[{"agent":"pi","agent_status":"working","agent_session":{"agent":"pi"}}]}}\n'
        ;;
      ws-blocked)
        printf '{"result":{"panes":[{"agent":"pi","agent_status":"blocked","agent_session":{"agent":"pi"}}]}}\n'
        ;;
      ws-unknown)
        printf '{"result":{"panes":[{"agent":"pi","agent_status":"unknown","agent_session":{"agent":"pi"}}]}}\n'
        ;;
      ws-persisted)
        printf '{"result":{"panes":[{"agent_status":"unknown","agent_session":{"agent":"pi"}}]}}\n'
        ;;
      *)
        printf '{"result":{"panes":[]}}\n'
        ;;
    esac
    ;;
esac
exit 0
EOF
  chmod +x "$fixture/bin/herdr"

  local real_fixture="${fixture:A}"
  cat > "$fixture/session/session.json" <<EOF
{"workspaces":[
  {"id":"ws-main","identity_cwd":"$real_fixture/repo.git/main","custom_name":"main"},
  {"id":"ws-a","identity_cwd":"$real_fixture/repo.git/a","custom_name":"a"},
  {"id":"ws-b","identity_cwd":"$real_fixture/repo.git/b","custom_name":"b"}
]}
EOF
}

# Cleanup from the manager must preserve the worktree hosting the overlay, just
# like direct wtclean preserves its current worktree. It must also close once
# instead of returning to the manager redraw loop after requesting pane close.
manager_fixture="$test_root/manager"
make_fixture "$manager_fixture"
: > "$manager_fixture/herdr.trace"
printf 'k\ny\n\n' | env \
  HOME="$manager_fixture/home" \
  PATH="$manager_fixture/bin:$PATH" \
  RDEV_DOTFILES="$repo_root" \
  HWS_MODE=manager \
  HWS_PROJECT_CWD="$manager_fixture/repo.git/a" \
  HERDR_SOCKET_PATH="$manager_fixture/session/herdr.sock" \
  HERDR_WORKSPACE_ID=ws-a \
  HERDR_PANE_ID=manager-overlay \
  HERDR_TRACE="$manager_fixture/herdr.trace" \
  zsh "$repo_root/herdr/plugins/worktree-sync/manager.sh" \
  > "$manager_fixture/output" 2>&1

[[ -d "$manager_fixture/repo.git/a" ]] || fail "manager removed its hosting worktree"
[[ ! -d "$manager_fixture/repo.git/b" ]] || fail "manager did not remove another merged worktree"
manager_renders=$(grep -c 'Worktree Manager —' "$manager_fixture/output" || true)
[[ "$manager_renders" == 1 ]] || fail "manager rendered $manager_renders times after one cleanup"
pane_closes=$(grep -c '^pane close manager-overlay$' "$manager_fixture/herdr.trace" || true)
[[ "$pane_closes" == 1 ]] || fail "manager requested pane close $pane_closes times"
workspace_closes=$(grep -c '^workspace close ws-b$' "$manager_fixture/herdr.trace" || true)
[[ "$workspace_closes" == 1 ]] || fail "manager requested workspace close $workspace_closes times for one removed worktree"

# A failed parallel removal must make the command fail and must not claim that
# every candidate was removed. A locked worktree deterministically exercises
# the same partial-cleanup path as a real failed git worktree remove.
failure_fixture="$test_root/failure"
make_fixture "$failure_fixture"
git --git-dir="$failure_fixture/repo.git" worktree lock "$failure_fixture/repo.git/a"
: > "$failure_fixture/herdr.trace"
set +e
printf 'y\n' | env \
  HOME="$failure_fixture/home" \
  PATH="$failure_fixture/bin:$PATH" \
  RDEV_DOTFILES="$repo_root" \
  HERDR_SOCKET_PATH="$failure_fixture/session/herdr.sock" \
  HERDR_TRACE="$failure_fixture/herdr.trace" \
  zsh -c 'cd "$1" && source "$2/zsh/functions/wtclean"' \
  zsh "$failure_fixture/repo.git/main" "$repo_root" \
  > "$failure_fixture/output" 2>&1
cleanup_status=$?
set -e

[[ "$cleanup_status" -ne 0 ]] || fail "partial cleanup returned success"
[[ -d "$failure_fixture/repo.git/a" ]] || fail "locked worktree unexpectedly disappeared"
[[ ! -d "$failure_fixture/repo.git/b" ]] || fail "successful sibling removal did not complete"
! grep -q '^Done\.$' "$failure_fixture/output" || fail "partial cleanup claimed Done"
grep -q 'merged-a' "$failure_fixture/output" || fail "partial cleanup did not identify the failed branch"

# Branches whose names normalize to the same temporary filename must retain
# independent PR states. Only the merged branch should be removed.
collision_fixture="$test_root/collision"
make_fixture "$collision_fixture"
git --git-dir="$collision_fixture/repo.git" branch feature/foo main
git --git-dir="$collision_fixture/repo.git" branch feature__foo main
git --git-dir="$collision_fixture/repo.git" worktree add -q "$collision_fixture/repo.git/feature-foo" feature/foo
git --git-dir="$collision_fixture/repo.git" worktree add -q "$collision_fixture/repo.git/feature__foo" feature__foo
cat > "$collision_fixture/bin/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "repo view") printf 'main\n' ;;
  "pr view")
    case "$3" in
      feature/foo) sleep 0.05; printf 'MERGED\n' ;;
      feature__foo) sleep 0.2; printf 'OPEN\n' ;;
      *) printf 'OPEN\n' ;;
    esac
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$collision_fixture/bin/gh"
: > "$collision_fixture/herdr.trace"
printf 'y\n' | env \
  HOME="$collision_fixture/home" \
  PATH="$collision_fixture/bin:$PATH" \
  RDEV_DOTFILES="$repo_root" \
  HERDR_SOCKET_PATH="$collision_fixture/session/herdr.sock" \
  HERDR_TRACE="$collision_fixture/herdr.trace" \
  zsh -c 'cd "$1" && source "$2/zsh/functions/wtclean"' \
  zsh "$collision_fixture/repo.git/main" "$repo_root" \
  > "$collision_fixture/output" 2>&1

[[ ! -d "$collision_fixture/repo.git/feature-foo" ]] || fail "merged colliding branch was not removed"
[[ -d "$collision_fixture/repo.git/feature__foo" ]] || fail "open colliding branch was removed"

# A clean checkout for a closed PR can be hibernated without losing the local
# branch. Reopening it later goes back through wtensure/hwtcreate.
closed_fixture="$test_root/closed"
make_fixture "$closed_fixture"
git --git-dir="$closed_fixture/repo.git" branch closed-pr main
git --git-dir="$closed_fixture/repo.git" worktree add -q "$closed_fixture/repo.git/closed-pr" closed-pr
cat > "$closed_fixture/bin/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "repo view") printf 'main\n' ;;
  "pr view")
    if [ "$3" = closed-pr ]; then printf 'CLOSED\n'; else printf 'OPEN\n'; fi
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$closed_fixture/bin/gh"
: > "$closed_fixture/herdr.trace"
printf 'y\n' | env \
  HOME="$closed_fixture/home" \
  PATH="$closed_fixture/bin:$PATH" \
  RDEV_DOTFILES="$repo_root" \
  HERDR_SOCKET_PATH="$closed_fixture/session/herdr.sock" \
  HERDR_TRACE="$closed_fixture/herdr.trace" \
  zsh -c 'cd "$1" && source "$2/zsh/functions/wtclean"' \
  zsh "$closed_fixture/repo.git/main" "$repo_root" \
  > "$closed_fixture/output" 2>&1

[[ ! -d "$closed_fixture/repo.git/closed-pr" ]] || fail "clean closed-PR worktree was not removed"
git --git-dir="$closed_fixture/repo.git" show-ref --verify --quiet refs/heads/closed-pr \
  || fail "closed-PR cleanup deleted the local branch"

# No-PR worktrees already contained in the default branch are removable. Every
# live agent remains protected, including idle and done agents whose process and
# conversation are still open. Persisted agent metadata alone is not a live
# agent. Dirty worktrees join the confirmation only when their newest local
# change is at least seven days old; recent local work must remain untouched.
stale_fixture="$test_root/stale"
make_fixture "$stale_fixture"
git --git-dir="$stale_fixture/repo.git" branch stale-dirty main
git --git-dir="$stale_fixture/repo.git" branch recent-dirty main
git --git-dir="$stale_fixture/repo.git" branch integrated-clean main
for state in idle done working blocked unknown persisted; do
  git --git-dir="$stale_fixture/repo.git" branch "integrated-$state" main
  git --git-dir="$stale_fixture/repo.git" worktree add -q \
    "$stale_fixture/repo.git/integrated-$state" "integrated-$state"
done
git --git-dir="$stale_fixture/repo.git" worktree add -q "$stale_fixture/repo.git/stale-dirty" stale-dirty
git --git-dir="$stale_fixture/repo.git" worktree add -q "$stale_fixture/repo.git/recent-dirty" recent-dirty
git --git-dir="$stale_fixture/repo.git" worktree add -q "$stale_fixture/repo.git/integrated-clean" integrated-clean
python3 - "$stale_fixture/session/session.json" "$stale_fixture/repo.git" <<'PY'
import json
import os
import sys

session_path, worktree_root = sys.argv[1:]
with open(session_path) as file:
    session = json.load(file)
for state in ("idle", "done", "working", "blocked", "unknown", "persisted"):
    worktree_path = os.path.realpath(os.path.join(worktree_root, f"integrated-{state}"))
    session["workspaces"].append({
        "id": f"ws-{state}",
        "identity_cwd": worktree_path,
        "custom_name": f"integrated-{state}",
        "tabs": [{"panes": {"1": {"agent_session": {"agent": "pi"}}}}],
    })
with open(session_path, "w") as file:
    json.dump(session, file)
PY
print -r -- stale >> "$stale_fixture/repo.git/stale-dirty/file"
print -r -- recent >> "$stale_fixture/repo.git/recent-dirty/file"
python3 - "$stale_fixture/repo.git/stale-dirty/file" <<'PY'
import os
import sys
import time

stale = time.time() - 8 * 24 * 60 * 60
os.utime(sys.argv[1], (stale, stale))
PY
cat > "$stale_fixture/bin/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "repo view") printf 'main\n' ;;
  "pr view") exit 1 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$stale_fixture/bin/gh"
: > "$stale_fixture/herdr.trace"
printf 'y\n' | env \
  HOME="$stale_fixture/home" \
  PATH="$stale_fixture/bin:$PATH" \
  RDEV_DOTFILES="$repo_root" \
  HERDR_SOCKET_PATH="$stale_fixture/session/herdr.sock" \
  HERDR_TRACE="$stale_fixture/herdr.trace" \
  zsh -c 'cd "$1" && source "$2/zsh/functions/wtclean"' \
  zsh "$stale_fixture/repo.git/main" "$repo_root" \
  > "$stale_fixture/output" 2>&1

[[ ! -d "$stale_fixture/repo.git/integrated-clean" ]] || fail "clean integrated worktree was not removed"
[[ ! -d "$stale_fixture/repo.git/integrated-persisted" ]] || fail "persisted agent metadata incorrectly protected an integrated worktree"
for state in idle done working blocked unknown; do
  [[ -d "$stale_fixture/repo.git/integrated-$state" ]] || fail "$state live agent did not protect its integrated worktree"
done
[[ ! -d "$stale_fixture/repo.git/stale-dirty" ]] || fail "stale dirty integrated worktree was not removed"
[[ -d "$stale_fixture/repo.git/recent-dirty" ]] || fail "recent dirty integrated worktree was removed"
grep -q 'stale local changes' "$stale_fixture/output" || fail "stale dirty candidate was not labeled"

# Safety checks must fail before Git can partially delete/unregister a checkout.
run_safety_cleanup() {
  local fixture="$1"
  printf 'y\n' | env \
    HOME="$fixture/home" PATH="$fixture/bin:$PATH" \
    RDEV_DOTFILES="$repo_root" HERDR_SOCKET_PATH="$fixture/session/herdr.sock" \
    HERDR_TRACE="$fixture/herdr.trace" \
    WTCLEAN_CONFIRM_ACTION="${WTCLEAN_CONFIRM_ACTION:-}" \
    WTCLEAN_TEST_MISSING_HERDR="${WTCLEAN_TEST_MISSING_HERDR:-0}" \
    zsh -c '
      command() {
        if [[ "$*" == "-v herdr" && "$WTCLEAN_TEST_MISSING_HERDR" == 1 ]]; then
          print "missing herdr cli" >> "$HERDR_TRACE"
          return 1
        fi
        builtin command "$@"
      }
      read() {
        if [[ "$1" == response && -n "$WTCLEAN_CONFIRM_ACTION" ]]; then
          eval "$WTCLEAN_CONFIRM_ACTION"
        fi
        builtin read "$@"
      }
      cd "$1" && source "$2/zsh/functions/wtclean"
    ' zsh "$fixture/repo.git/main" "$repo_root" > "$fixture/output" 2>&1
}

permission_fixture="$test_root/permission"
make_fixture "$permission_fixture"
mkdir -p "$permission_fixture/repo.git/a/supabase/generated"
print protected > "$permission_fixture/repo.git/a/supabase/generated/file.sql"
print '/supabase/' >> "$permission_fixture/repo.git/info/exclude"
chmod a-w "$permission_fixture/repo.git/a/supabase/generated"
: > "$permission_fixture/herdr.trace"
set +e
run_safety_cleanup "$permission_fixture"
permission_status=$?
set -e
if (( EUID != 0 )); then
  [[ "$permission_status" -ne 0 ]] || fail "permission blocker returned success"
  [[ -f "$permission_fixture/repo.git/a/.git" ]] || fail "permission failure destroyed .git"
  [[ -f "$permission_fixture/repo.git/a/supabase/generated/file.sql" ]] || fail "permission failure removed local files"
  git --git-dir="$permission_fixture/repo.git" worktree list --porcelain | grep -Fq "$permission_fixture/repo.git/a" \
    || fail "permission failure unregistered the worktree"
  ! grep -q '^workspace close ws-a$' "$permission_fixture/herdr.trace" || fail "permission blocker closed its workspace"
fi
chmod u+w "$permission_fixture/repo.git/a/supabase/generated" 2>/dev/null || true

status_fixture="$test_root/status-error"
make_fixture "$status_fixture"
real_git=$(command -v git)
printf '#!/bin/sh\ncase "$*" in *" status --porcelain=v1"*) printf "status failure\\n" >> "$HERDR_TRACE"; exit 1;; esac\nexec %q "$@"\n' "$real_git" > "$status_fixture/bin/git"
chmod +x "$status_fixture/bin/git"
: > "$status_fixture/herdr.trace"
if run_safety_cleanup "$status_fixture"; then fail "failed Git status returned success"; fi
grep -q '^status failure$' "$status_fixture/herdr.trace" || fail "Git status failure stub was bypassed"
[[ -f "$status_fixture/repo.git/a/.git" ]] || fail "failed Git status was treated as clean"

live_dirty_fixture="$test_root/live-dirty"
make_fixture "$live_dirty_fixture"
print pending >> "$live_dirty_fixture/repo.git/a/file"
python3 - "$live_dirty_fixture/repo.git/a/file" "$live_dirty_fixture/session/session.json" <<'PY'
import json, os, sys, time
os.utime(sys.argv[1], (time.time() - 8 * 86400,) * 2)
with open(sys.argv[2]) as f:
    data = json.load(f)
data['workspaces'][1]['id'] = 'ws-working'
with open(sys.argv[2], 'w') as f:
    json.dump(data, f)
PY
: > "$live_dirty_fixture/herdr.trace"
run_safety_cleanup "$live_dirty_fixture" || true
[[ -f "$live_dirty_fixture/repo.git/a/.git" ]] || fail "stale-dirty checkout bypassed live-agent protection"

unknown_fixture="$test_root/unknown-agent"
make_fixture "$unknown_fixture"
mv "$unknown_fixture/bin/herdr" "$unknown_fixture/bin/herdr-real"
printf '#!/bin/sh\ncase "$1 $2" in "pane list") exit 1;; esac\nexec %q "$@"\n' "$unknown_fixture/bin/herdr-real" > "$unknown_fixture/bin/herdr"
chmod +x "$unknown_fixture/bin/herdr"
: > "$unknown_fixture/herdr.trace"
run_safety_cleanup "$unknown_fixture" || true
[[ -f "$unknown_fixture/repo.git/a/.git" ]] || fail "failed agent lookup was treated as absent"

changed_fixture="$test_root/changed-after-confirmation"
make_fixture "$changed_fixture"
: > "$changed_fixture/herdr.trace"
WTCLEAN_CONFIRM_ACTION="print new-work >> ${(q)changed_fixture}/repo.git/a/file" run_safety_cleanup "$changed_fixture" || true
[[ -f "$changed_fixture/repo.git/a/.git" ]] || fail "clean candidate changed while confirming was force-deleted"

switched_fixture="$test_root/switched-after-confirmation"
make_fixture "$switched_fixture"
: > "$switched_fixture/herdr.trace"
WTCLEAN_CONFIRM_ACTION="git -C ${(q)switched_fixture}/repo.git/a branch -m trunk" run_safety_cleanup "$switched_fixture" || true
[[ -f "$switched_fixture/repo.git/a/.git" ]] || fail "candidate switched to a protected branch was deleted"

new_tip_fixture="$test_root/merged-pr-new-tip"
make_fixture "$new_tip_fixture"
git -C "$new_tip_fixture/repo.git/a" config user.name Test
git -C "$new_tip_fixture/repo.git/a" config user.email test@example.com
print unpushed >> "$new_tip_fixture/repo.git/a/file"
git -C "$new_tip_fixture/repo.git/a" commit -qam 'new work after merged PR'
: > "$new_tip_fixture/herdr.trace"
run_safety_cleanup "$new_tip_fixture" || true
[[ -f "$new_tip_fixture/repo.git/a/.git" ]] || fail "old merged PR incorrectly proved integration of new local tip"

missing_cli_fixture="$test_root/missing-herdr"
make_fixture "$missing_cli_fixture"
: > "$missing_cli_fixture/herdr.trace"
if WTCLEAN_TEST_MISSING_HERDR=1 run_safety_cleanup "$missing_cli_fixture"; then
  fail "missing Herdr CLI returned success"
fi
grep -q '^missing herdr cli$' "$missing_cli_fixture/herdr.trace" || fail "missing CLI guard was not exercised"
[[ -f "$missing_cli_fixture/repo.git/a/.git" ]] || fail "missing Herdr CLI was treated as verified absence"

make_stale_safety_fixture() {
  make_fixture "$1"
  print pending >> "$1/repo.git/a/file"
  python3 - "$1/repo.git/a/file" <<'PY'
import os, sys, time
os.utime(sys.argv[1], (time.time() - 8 * 86400,) * 2)
PY
  : > "$1/herdr.trace"
}

copied_fixture="$test_root/copied-old-work"
make_stale_safety_fixture "$copied_fixture"
if WTCLEAN_CONFIRM_ACTION="cp -p ${(q)copied_fixture}/repo.git/a/file ${(q)copied_fixture}/repo.git/a/new-old-file" run_safety_cleanup "$copied_fixture"; then
  fail "new backdated work returned success"
fi
[[ -f "$copied_fixture/repo.git/a/new-old-file" ]] || fail "newly copied old file was deleted"
[[ -f "$copied_fixture/repo.git/a/.git" ]] || fail "new backdated work was not protected"

preserved_fixture="$test_root/preserved-mtime"
make_stale_safety_fixture "$preserved_fixture"
if WTCLEAN_CONFIRM_ACTION="cp -p ${(q)preserved_fixture}/repo.git/a/file ${(q)preserved_fixture}/reference; print changed >> ${(q)preserved_fixture}/repo.git/a/file; touch -r ${(q)preserved_fixture}/reference ${(q)preserved_fixture}/repo.git/a/file" run_safety_cleanup "$preserved_fixture"; then
  fail "changed dirty contents returned success"
fi
[[ -f "$preserved_fixture/repo.git/a/.git" ]] || fail "changed contents with preserved mtime were deleted"

fingerprint_fixture="$test_root/fingerprint-error"
make_stale_safety_fixture "$fingerprint_fixture"
printf '#!/bin/sh\ncase "$*" in *" diff --binary"*) if test -f %q; then printf "fingerprint failure\\n" >> "$HERDR_TRACE"; exit 1; fi;; esac\nexec %q "$@"\n' "$fingerprint_fixture/fail-inspection" "$real_git" > "$fingerprint_fixture/bin/git"
chmod +x "$fingerprint_fixture/bin/git"
if WTCLEAN_CONFIRM_ACTION="touch ${(q)fingerprint_fixture}/fail-inspection" run_safety_cleanup "$fingerprint_fixture"; then
  fail "failed fingerprint inspection returned success"
fi
grep -q '^fingerprint failure$' "$fingerprint_fixture/herdr.trace" || fail "fingerprint failure stub was bypassed"
[[ -f "$fingerprint_fixture/repo.git/a/.git" ]] || fail "failed fingerprint inspection allowed force removal"

if (( failures > 0 )); then
  print -u2 -- "$failures wtclean Herdr cleanup test(s) failed"
  exit 1
fi

print 'wtclean Herdr cleanup tests passed'
