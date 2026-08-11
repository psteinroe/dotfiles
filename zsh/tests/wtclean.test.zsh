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
  mkdir -p "$fixture/seed" "$fixture/bin" "$fixture/home" "$fixture/session"
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
  "workspace get") printf '{"result":{}}\n' ;;
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

  cat > "$fixture/session/session.json" <<EOF
{"workspaces":[
  {"id":"ws-main","identity_cwd":"$fixture/repo.git/main","custom_name":"main"},
  {"id":"ws-a","identity_cwd":"$fixture/repo.git/a","custom_name":"a"},
  {"id":"ws-b","identity_cwd":"$fixture/repo.git/b","custom_name":"b"}
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

# No-PR worktrees already contained in the default branch are removable. Idle
# and done agents do not make their workspace active, and persisted agent
# metadata alone is not a live agent. Working, blocked, and unknown live agents
# remain protected. Dirty worktrees join the confirmation only when their newest
# local change is at least seven days old; recent local work must remain untouched.
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
[[ ! -d "$stale_fixture/repo.git/integrated-idle" ]] || fail "idle agent incorrectly protected an integrated worktree"
[[ ! -d "$stale_fixture/repo.git/integrated-done" ]] || fail "done agent incorrectly protected an integrated worktree"
[[ ! -d "$stale_fixture/repo.git/integrated-persisted" ]] || fail "persisted agent metadata incorrectly protected an integrated worktree"
for state in working blocked unknown; do
  [[ -d "$stale_fixture/repo.git/integrated-$state" ]] || fail "$state agent did not protect its integrated worktree"
done
[[ ! -d "$stale_fixture/repo.git/stale-dirty" ]] || fail "stale dirty integrated worktree was not removed"
[[ -d "$stale_fixture/repo.git/recent-dirty" ]] || fail "recent dirty integrated worktree was removed"
grep -q 'stale local changes' "$stale_fixture/output" || fail "stale dirty candidate was not labeled"

if (( failures > 0 )); then
  print -u2 -- "$failures wtclean Herdr cleanup test(s) failed"
  exit 1
fi

print 'wtclean Herdr cleanup tests passed'
