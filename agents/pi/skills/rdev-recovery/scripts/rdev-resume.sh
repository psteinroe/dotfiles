#!/usr/bin/env bash
set -euo pipefail

host=rdev
session=hellomateo
agents=()
protected=()
min_memory_mib=10240
max_load=10
max_cpu_psi=35
max_memory_psi=2
critical_memory_mib=3072
critical_load=28
critical_cpu_psi=80
critical_memory_psi=15
sample_interval=15
monitor_seconds=300
interrupt_on_critical=0

usage() {
  cat <<'EOF'
Usage: rdev-resume.sh [options] --agent TARGET [--agent TARGET ...]

Send "continue" to restored Pi agents in priority order, gated by remote CPU
and memory headroom. Submission does not wait for an agent's turn to finish.

Options:
  --host HOST
  --session NAME
  --agent NAME_OR_PANE       Repeat in priority order
  --protect NAME_OR_PANE     Never interrupt this target; repeatable
  --min-memory-mib N         Submission gate (default: 10240)
  --max-load N               Submission gate (default: 10)
  --max-cpu-psi N            Submission gate, avg10 percent (default: 35)
  --max-memory-psi N         Submission gate, avg10 percent (default: 2)
  --sample-interval N        Seconds between samples (default: 15)
  --monitor-seconds N        Guard duration after submission (default: 300)
  --interrupt-on-critical    Ctrl-C newest unprotected turn at critical pressure
EOF
}

while (($#)); do
  case "$1" in
    --host) host=${2:?missing host}; shift 2 ;;
    --session) session=${2:?missing session}; shift 2 ;;
    --agent) agents+=("${2:?missing agent}"); shift 2 ;;
    --protect) protected+=("${2:?missing protected target}"); shift 2 ;;
    --min-memory-mib) min_memory_mib=${2:?missing value}; shift 2 ;;
    --max-load) max_load=${2:?missing value}; shift 2 ;;
    --max-cpu-psi) max_cpu_psi=${2:?missing value}; shift 2 ;;
    --max-memory-psi) max_memory_psi=${2:?missing value}; shift 2 ;;
    --sample-interval) sample_interval=${2:?missing value}; shift 2 ;;
    --monitor-seconds) monitor_seconds=${2:?missing value}; shift 2 ;;
    --interrupt-on-critical) interrupt_on_critical=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

((${#agents[@]})) || { echo 'At least one --agent is required.' >&2; exit 2; }
[[ $session =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Invalid session: $session" >&2; exit 2; }
for target in "${agents[@]}" "${protected[@]}"; do
  [[ $target =~ ^[A-Za-z0-9_.:-]+$ ]] || { echo "Invalid agent target: $target" >&2; exit 2; }
done
for value in "$min_memory_mib" "$sample_interval" "$monitor_seconds"; do
  [[ $value =~ ^[0-9]+$ ]] || { echo "Expected an integer, got: $value" >&2; exit 2; }
done
for value in "$max_load" "$max_cpu_psi" "$max_memory_psi"; do
  [[ $value =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "Expected a number, got: $value" >&2; exit 2; }
done

ssh_opts=(-o ControlMaster=no -o ControlPath=none -o BatchMode=yes -o ConnectTimeout=8)
submitted=()
interrupted=()
min_observed_memory=999999
peak_observed_load=0

remote_health() {
  ssh "${ssh_opts[@]}" "$host" python3 - <<'PY'
from pathlib import Path

def psi(path):
    for line in Path(path).read_text().splitlines():
        if line.startswith("some "):
            for field in line.split()[1:]:
                if field.startswith("avg10="):
                    return float(field.split("=", 1)[1])
    return 0.0

load = float(Path("/proc/loadavg").read_text().split()[0])
mem_kib = next(int(line.split()[1]) for line in Path("/proc/meminfo").read_text().splitlines() if line.startswith("MemAvailable:"))
print(f"{load} {mem_kib // 1024} {psi('/proc/pressure/cpu')} {psi('/proc/pressure/memory')}")
PY
}

sample_health() {
  local values
  values=$(remote_health) || { echo "$(date -u +%FT%TZ) $host unreachable" >&2; return 1; }
  read -r current_load current_memory current_cpu_psi current_memory_psi <<<"$values"
  [[ -n ${current_memory:-} ]] || { echo "Invalid health sample: $values" >&2; return 1; }
  if ((current_memory < min_observed_memory)); then min_observed_memory=$current_memory; fi
  if awk -v a="$current_load" -v b="$peak_observed_load" 'BEGIN { exit !(a > b) }'; then peak_observed_load=$current_load; fi
  printf '%s load1=%s mem_available_mib=%s cpu_psi10=%s mem_psi10=%s\n' \
    "$(date -u +%FT%TZ)" "$current_load" "$current_memory" "$current_cpu_psi" "$current_memory_psi"
}

agent_state() {
  local target=$1
  ssh "${ssh_opts[@]}" "$host" \
    "export PATH=\"\$HOME/.nix-profile/bin:\$PATH\"; herdr --session '$session' agent get '$target'" |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["agent"].get("agent_status", "unknown"))'
}

prompt_agent() {
  local target=$1
  ssh "${ssh_opts[@]}" "$host" \
    "export PATH=\"\$HOME/.nix-profile/bin:\$PATH\"; herdr --session '$session' agent prompt '$target' 'continue'" >/dev/null
}

is_protected() {
  local needle=$1 item
  for item in "${protected[@]}"; do [[ $item == "$needle" ]] && return 0; done
  return 1
}

was_interrupted() {
  local needle=$1 item
  for item in "${interrupted[@]}"; do [[ $item == "$needle" ]] && return 0; done
  return 1
}

interrupt_newest_unprotected() {
  local index target state
  for ((index=${#submitted[@]}-1; index>=0; index--)); do
    target=${submitted[index]}
    is_protected "$target" && continue
    was_interrupted "$target" && continue
    state=$(agent_state "$target" 2>/dev/null || echo unknown)
    [[ $state == working ]] || continue
    echo "$(date -u +%FT%TZ) critical pressure: interrupting $target" >&2
    ssh "${ssh_opts[@]}" "$host" \
      "export PATH=\"\$HOME/.nix-profile/bin:\$PATH\"; herdr --session '$session' agent send-keys '$target' ctrl+c" >/dev/null
    interrupted+=("$target")
    return 0
  done
  echo 'Critical pressure detected, but no unprotected resumed target is working.' >&2
  return 1
}

is_safe() {
  awk -v l="$current_load" -v m="$current_memory" -v c="$current_cpu_psi" -v p="$current_memory_psi" \
    -v ml="$max_load" -v mm="$min_memory_mib" -v mc="$max_cpu_psi" -v mp="$max_memory_psi" \
    'BEGIN { exit !(l <= ml && m >= mm && c <= mc && p <= mp) }'
}

is_critical() {
  awk -v l="$current_load" -v m="$current_memory" -v c="$current_cpu_psi" -v p="$current_memory_psi" \
    -v cl="$critical_load" -v cm="$critical_memory_mib" -v cc="$critical_cpu_psi" -v cp="$critical_memory_psi" \
    'BEGIN { exit !(l > cl || m < cm || c > cc || p > cp) }'
}

for target in "${agents[@]}"; do
  state=$(agent_state "$target")
  if [[ $state == working || $state == blocked ]]; then
    printf '%s already %s; not sending a duplicate prompt\n' "$target" "$state"
    submitted+=("$target")
    continue
  fi

  safe_samples=0
  for ((attempt=1; attempt<=80; attempt++)); do
    sample_health
    if is_critical; then
      if ((interrupt_on_critical)); then interrupt_newest_unprotected || exit 3; else exit 3; fi
    fi
    if is_safe; then safe_samples=$((safe_samples + 1)); else safe_samples=0; fi
    ((safe_samples >= 2)) && break
    sleep "$sample_interval"
  done
  ((safe_samples >= 2)) || { echo "Resource gate withheld continue from $target." >&2; exit 4; }

  prompt_agent "$target"
  submitted+=("$target")
  printf '%s submitted continue to %s\n' "$(date -u +%FT%TZ)" "$target"
  sleep "$sample_interval"
done

guard_samples=$(((monitor_seconds + sample_interval - 1) / sample_interval))
for ((sample=1; sample<=guard_samples; sample++)); do
  sample_health
  if is_critical; then
    if ((interrupt_on_critical)); then interrupt_newest_unprotected || exit 3; else exit 3; fi
  fi
  ((sample == guard_samples)) || sleep "$sample_interval"
done

printf 'recovery guard complete: min_memory_mib=%s peak_load1=%s interrupted=%s\n' \
  "$min_observed_memory" "$peak_observed_load" "${interrupted[*]:-none}"
