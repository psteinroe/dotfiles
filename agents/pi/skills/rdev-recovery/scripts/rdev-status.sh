#!/usr/bin/env bash
set -euo pipefail

host=rdev
public_host=rdev-exe
sessions=(hellomateo postgres-conductor)

usage() {
  cat <<'EOF'
Usage: rdev-status.sh [--host HOST] [--public-host HOST] [--session NAME ...]

Read-only health report for the rdev VM and its remote Herdr sessions.
EOF
}

custom_sessions=0
while (($#)); do
  case "$1" in
    --host) host=${2:?missing host}; shift 2 ;;
    --public-host) public_host=${2:?missing public host}; shift 2 ;;
    --session)
      if ((custom_sessions == 0)); then sessions=(); custom_sessions=1; fi
      sessions+=("${2:?missing session}")
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for session in "${sessions[@]}"; do
  [[ $session =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Invalid session: $session" >&2; exit 2; }
done

ssh_opts=(-o ControlMaster=no -o ControlPath=none -o BatchMode=yes -o ConnectTimeout=8)

printf '%s\n' '=== provider ==='
ssh "${ssh_opts[@]}" exe.dev ls --json | python3 -c '
import json, sys
for vm in json.load(sys.stdin).get("vms", []):
    if vm.get("vm_name") == "psteinroe-dev":
        name = vm.get("vm_name")
        status = vm.get("status")
        memory_gib = vm.get("memory_capacity_bytes", 0) // 2**30
        print(f"{name}: {status} ({memory_gib} GiB)")
        break
else:
    raise SystemExit("psteinroe-dev not found")
'

printf '\n%s\n' '=== transport ==='
for target in "$public_host" "$host"; do
  if output=$(ssh "${ssh_opts[@]}" "$target" 'printf "%s " "$(hostname)"; uptime' 2>&1); then
    printf '%-12s %s\n' "$target" "$output"
  else
    printf '%-12s UNREACHABLE: %s\n' "$target" "$output"
  fi
done

printf '\n%s\n' '=== machine ==='
ssh "${ssh_opts[@]}" "$host" 'bash -s' <<'REMOTE'
set -u
uptime
free -h
printf 'load: '; cat /proc/loadavg
printf 'cpu pressure: '; tr '\n' ' ' </proc/pressure/cpu; echo
printf 'memory pressure: '; tr '\n' ' ' </proc/pressure/memory; echo
printf 'disk /: '; df -h / | awk 'NR == 2 { print $5 " used, " $4 " free" }'
printf 'system: '; systemctl is-system-running 2>&1 || true
printf 'failed units: '; systemctl --failed --no-legend --plain 2>/dev/null | wc -l
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
for service in t3code moshi-hook; do
  printf '%-14s ' "$service"
  systemctl --user is-active "$service" 2>&1 || true
done
printf 'pi processes: '; pgrep -u "$USER" -x pi 2>/dev/null | wc -l
printf 'herdr servers: '; pgrep -u "$USER" -f '/herdr server$' 2>/dev/null | wc -l
printf 'docker containers: '; docker ps -q 2>/dev/null | wc -l
printf 'unhealthy containers: '; docker ps --filter health=unhealthy -q 2>/dev/null | wc -l
REMOTE

printf '\n%s\n' '=== herdr sessions ==='
for session in "${sessions[@]}"; do
  printf '%s: ' "$session"
  if output=$(ssh "${ssh_opts[@]}" "$host" "export PATH=\"\$HOME/.nix-profile/bin:\$PATH\"; herdr --session '$session' status >/dev/null && herdr --session '$session' agent list" 2>&1); then
    python3 -c '
import json, sys
agents = json.load(sys.stdin)["result"]["agents"]
states = {}
for agent in agents:
    state = agent.get("agent_status", "unknown")
    states[state] = states.get(state, 0) + 1
print(f"live; agents={len(agents)} states={states}")
' <<<"$output"
  else
    printf 'UNAVAILABLE: %s\n' "$output"
  fi
done
