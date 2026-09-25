#!/usr/bin/env bash
set -euo pipefail

host=rdev
trigger_percent=90
target_percent=80
journal_size=200M
force=0
dry_run=0
confirmed=0

usage() {
  cat <<'EOF'
Usage: rdev-cleanup.sh [options]

Conservatively reclaim reproducible data on the rdev VM when the root
filesystem reaches the trigger percentage. Docker volumes, Git worktrees,
Pi transcripts, and active containers are preserved.

Options:
  --host HOST                 SSH host (default: rdev)
  --trigger-percent PERCENT   Start cleanup at this usage (default: 90)
  --target-percent PERCENT    Stop after reaching this usage (default: 80)
  --journal-size SIZE         Retain this much system journal data (default: 200M)
  --dry-run                   Show status and cleanup candidates without changing data
  --force                     Clean even when usage is below the trigger; run every phase
  --yes                       Authorize cleanup
  -h, --help                  Show this help
EOF
}

while (($#)); do
  case "$1" in
    --host) host=${2:?missing host}; shift 2 ;;
    --trigger-percent) trigger_percent=${2:?missing trigger percentage}; shift 2 ;;
    --target-percent) target_percent=${2:?missing target percentage}; shift 2 ;;
    --journal-size) journal_size=${2:?missing journal size}; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --force) force=1; shift ;;
    --yes) confirmed=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ $host =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Invalid host: $host" >&2; exit 2; }
[[ $trigger_percent =~ ^[0-9]+$ ]] && ((trigger_percent >= 1 && trigger_percent <= 100)) || {
  echo "Trigger percentage must be an integer from 1 to 100" >&2
  exit 2
}
[[ $target_percent =~ ^[0-9]+$ ]] && ((target_percent >= 1 && target_percent <= 99)) || {
  echo "Target percentage must be an integer from 1 to 99" >&2
  exit 2
}
((target_percent < trigger_percent)) || {
  echo "Target percentage must be lower than trigger percentage" >&2
  exit 2
}
[[ $journal_size =~ ^[0-9]+[KMG]?$ ]] || { echo "Invalid journal size: $journal_size" >&2; exit 2; }

if ((dry_run == 0 && confirmed == 0)); then
  echo "Cleanup requires --yes. Use --dry-run to inspect candidates." >&2
  exit 2
fi

ssh_opts=(-o ControlMaster=no -o ControlPath=none -o BatchMode=yes -o ConnectTimeout=8)
ssh "${ssh_opts[@]}" "$host" bash -s -- \
  "$trigger_percent" "$target_percent" "$journal_size" "$force" "$dry_run" <<'REMOTE'
set -u

trigger_percent=$1
target_percent=$2
journal_size=$3
force=$4
dry_run=$5
failures=0

usage_percent() {
  df -P / | awk 'NR == 2 { value=$5; sub(/%$/, "", value); print value }'
}

free_space() {
  df -hP / | awk 'NR == 2 { print $4 }'
}

used_kib() {
  df -Pk / | awk 'NR == 2 { print $3 }'
}

print_disk() {
  printf 'disk /: %s%% used, %s free\n' "$(usage_percent)" "$(free_space)"
}

run_optional() {
  if ! "$@"; then
    printf 'WARNING: command failed: ' >&2
    printf '%q ' "$@" >&2
    printf '\n' >&2
    failures=$((failures + 1))
  fi
}

show_candidate() {
  path=$1
  if [[ -e $path ]]; then
    if command -v timeout >/dev/null 2>&1; then
      timeout 30 du -sh -- "$path" 2>/dev/null || printf 'size timed out: %s\n' "$path"
    else
      du -sh -- "$path" 2>/dev/null || true
    fi
  fi
}

printf '%s\n' '=== rdev disk cleanup ==='
print_disk
printf 'trigger: %s%%; target: %s%%\n' "$trigger_percent" "$target_percent"
printf '%s\n' 'protected: Docker volumes, Git worktrees, Pi transcripts, active containers'

if ((dry_run)); then
  printf '\n%s\n' '=== cleanup candidates ==='
  for path in \
    "$HOME/Developer/.turbo" \
    "$HOME/.cache" \
    "$HOME/.npm/_cacache" \
    "$HOME/.npm/_npx" \
    "$HOME/.bun/install/cache" \
    "$HOME/.gradle/caches"
  do
    show_candidate "$path"
  done
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    printf '\n%s\n' '=== Docker ==='
    docker system df || true
  fi
  if sudo -n true 2>/dev/null; then
    printf '\n%s\n' '=== journal ==='
    sudo -n journalctl --disk-usage 2>/dev/null || true
  fi
  exit 0
fi

current_percent=$(usage_percent)
if ((force == 0 && current_percent < trigger_percent)); then
  printf 'Below trigger; no cleanup needed.\n'
  exit 0
fi

before_kib=$(used_kib)

printf '\n%s\n' '=== system caches and journals ==='
if sudo -n true 2>/dev/null; then
  if command -v apt-get >/dev/null 2>&1; then
    run_optional sudo -n apt-get clean
  fi
  if command -v journalctl >/dev/null 2>&1; then
    run_optional sudo -n journalctl --vacuum-size="$journal_size"
  fi
else
  printf '%s\n' 'WARNING: passwordless sudo unavailable; skipping system cleanup' >&2
  failures=$((failures + 1))
fi
print_disk
if ((force == 0 && $(usage_percent) <= target_percent)); then
  printf 'Target reached after system cleanup.\n'
  exit 0
fi

printf '\n%s\n' '=== unused Docker data ==='
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  run_optional docker builder prune -af
  run_optional docker container prune -f
  run_optional docker image prune -af
else
  printf '%s\n' 'WARNING: Docker unavailable; skipping Docker cleanup' >&2
  failures=$((failures + 1))
fi
print_disk
if ((force == 0 && $(usage_percent) <= target_percent)); then
  printf 'Target reached after Docker cleanup.\n'
  exit 0
fi

printf '\n%s\n' '=== reproducible user caches ==='
run_optional rm -rf -- "$HOME/Developer/.turbo"
if [[ -d $HOME/.cache ]]; then
  while IFS= read -r -d '' entry; do
    run_optional rm -rf -- "$entry"
  done < <(find "$HOME/.cache" -mindepth 1 -maxdepth 1 -print0)
fi
for path in \
  "$HOME/.npm/_cacache" \
  "$HOME/.npm/_npx" \
  "$HOME/.bun/install/cache" \
  "$HOME/.gradle/caches"
do
  run_optional rm -rf -- "$path"
done

after_kib=$(used_kib)
reclaimed_kib=$((before_kib - after_kib))
((reclaimed_kib < 0)) && reclaimed_kib=0
printf '\nReclaimed approximately %d GiB.\n' "$((reclaimed_kib / 1024 / 1024))"
print_disk

current_percent=$(usage_percent)
if ((current_percent > target_percent)); then
  printf 'WARNING: disk usage remains above the %s%% target; inspect protected data manually.\n' "$target_percent" >&2
  exit 3
fi
if ((failures > 0)); then
  printf 'WARNING: cleanup reached the target with %d failed optional command(s).\n' "$failures" >&2
fi
REMOTE
