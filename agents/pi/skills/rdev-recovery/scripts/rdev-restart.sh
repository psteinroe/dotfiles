#!/usr/bin/env bash
set -euo pipefail

vm=psteinroe-dev
host=rdev
public_host=rdev-exe
timeout=300
confirmed=0

usage() {
  cat <<'EOF'
Usage: rdev-restart.sh --yes [--vm NAME] [--host HOST] [--public-host HOST] [--timeout SECONDS]

Restart an exe.dev VM, then wait for its public and private SSH paths.
--yes is required because restarting terminates all live guest processes.
EOF
}

while (($#)); do
  case "$1" in
    --yes) confirmed=1; shift ;;
    --vm) vm=${2:?missing VM name}; shift 2 ;;
    --host) host=${2:?missing host}; shift 2 ;;
    --public-host) public_host=${2:?missing public host}; shift 2 ;;
    --timeout) timeout=${2:?missing timeout}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if ((confirmed == 0)); then
  echo 'Refusing to restart without --yes.' >&2
  exit 2
fi
if [[ ! $timeout =~ ^[0-9]+$ ]] || ((timeout < 10)); then
  echo '--timeout must be an integer of at least 10 seconds.' >&2
  exit 2
fi

ssh_opts=(-o ControlMaster=no -o ControlPath=none -o BatchMode=yes -o ConnectTimeout=5)

printf 'Restarting %s through exe.dev...\n' "$vm"
ssh "${ssh_opts[@]}" exe.dev restart "$vm" --json

wait_for_ssh() {
  local target=$1 deadline=$((SECONDS + timeout)) attempt=0
  while ((SECONDS < deadline)); do
    attempt=$((attempt + 1))
    if ssh "${ssh_opts[@]}" "$target" 'printf ready' 2>/dev/null | grep -qx ready; then
      printf '%s recovered after %d attempt(s) at %s\n' "$target" "$attempt" "$(date -u +%FT%TZ)"
      return 0
    fi
    sleep 5
  done
  printf '%s did not recover within %ss\n' "$target" "$timeout" >&2
  return 1
}

wait_for_ssh "$public_host"
wait_for_ssh "$host"

ssh "${ssh_opts[@]}" "$host" 'hostname; uptime; systemctl is-system-running'
