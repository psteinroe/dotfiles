#!/usr/bin/env bash
set -euo pipefail

host=rdev
sessions=(hellomateo postgres-conductor)

usage() {
  cat <<'EOF'
Usage: rdev-interrupted.sh [--host HOST] [--session NAME ...]

Classify restored Pi transcripts as interrupted or settled from their final
meaningful JSONL entry. This is read-only evidence, not an automatic prompt.
EOF
}

custom_sessions=0
while (($#)); do
  case "$1" in
    --host) host=${2:?missing host}; shift 2 ;;
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
session_csv=$(IFS=,; echo "${sessions[*]}")
ssh_opts=(-o ControlMaster=no -o ControlPath=none -o BatchMode=yes -o ConnectTimeout=8)

ssh "${ssh_opts[@]}" "$host" "SESSIONS='$session_csv' bash -s" <<'REMOTE'
export PATH="$HOME/.nix-profile/bin:$PATH"
python3 - <<'PY'
import json
import os
import subprocess
from pathlib import Path

print("session\ttarget\tstate\tverdict\tlast_timestamp\tworkspace\ttranscript")
for session in filter(None, os.environ["SESSIONS"].split(",")):
    result = subprocess.run(
        ["herdr", "--session", session, "agent", "list"],
        check=True,
        capture_output=True,
        text=True,
    )
    agents = json.loads(result.stdout)["result"]["agents"]
    for agent in agents:
        target = agent.get("name") or agent.get("pane_id") or "unknown"
        state = agent.get("agent_status", "unknown")
        workspace = agent.get("workspace_id", "unknown")
        transcript = (agent.get("agent_session") or {}).get("value")
        verdict = "unknown"
        timestamp = "-"
        if transcript and Path(transcript).is_file():
            latest = None
            with open(transcript, encoding="utf-8", errors="replace") as handle:
                for line in handle:
                    try:
                        entry = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if entry.get("type") == "message" and isinstance(entry.get("message"), dict):
                        latest = entry
            if latest:
                timestamp = latest.get("timestamp", "-")
                message = latest["message"]
                role = message.get("role")
                content = message.get("content")
                types = [part.get("type") for part in content if isinstance(part, dict)] if isinstance(content, list) else []
                if role in {"user", "toolResult"}:
                    verdict = "interrupted"
                elif role == "assistant" and "toolCall" in types and (not types or types[-1] != "text"):
                    verdict = "interrupted"
                elif role == "assistant" and "text" in types:
                    verdict = "settled"
        if state == "working":
            verdict = "active"
        elif state == "blocked":
            verdict = "blocked"
        print(f"{session}\t{target}\t{state}\t{verdict}\t{timestamp}\t{workspace}\t{transcript or '-'}")
PY
REMOTE
