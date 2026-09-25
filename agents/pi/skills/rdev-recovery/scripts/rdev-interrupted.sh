#!/usr/bin/env bash
set -euo pipefail

host=rdev
sessions=(hellomateo postgres-conductor)

usage() {
  cat <<'EOF'
Usage: rdev-interrupted.sh [--host HOST] [--session NAME ...]

Classify restored Pi transcripts from their final meaningful JSONL entry and
surface unclosed background-task lifecycles. This is read-only evidence, not an
automatic prompt.
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
import re
import subprocess
from pathlib import Path

TERMINAL_TASK_STATES = {"aborted", "cancelled", "canceled", "done", "failed", "timed_out", "timeout"}
TASK_STATE_PATTERN = re.compile(r"(task-\d+) \[([a-z_]+)\]")
TASK_START_PATTERN = re.compile(r'Started (task-\d+) ["“]([^"”]+)')


def message_text(message):
    content = message.get("content")
    if not isinstance(content, list):
        return ""
    return "\n".join(
        str(part.get("text", ""))
        for part in content
        if isinstance(part, dict) and part.get("type") == "text"
    )


print("session\ttarget\tstate\tverdict\tlast_timestamp\tpending_tasks\tbackground_evidence\tworkspace\ttranscript")
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
        active_tasks = {}
        if transcript and Path(transcript).is_file():
            latest = None
            with open(transcript, encoding="utf-8", errors="replace") as handle:
                for line in handle:
                    try:
                        entry = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    entry_type = entry.get("type")
                    if entry_type == "message" and isinstance(entry.get("message"), dict):
                        latest = entry
                        message = entry["message"]
                        if message.get("role") != "toolResult":
                            continue
                        text = message_text(message)
                        tool_name = message.get("toolName")
                        if tool_name in {"start_background_command", "start_subagent"}:
                            match = TASK_START_PATTERN.search(text)
                            if match:
                                task_id, title = match.groups()
                                active_tasks[task_id] = {
                                    "started": entry.get("timestamp", "-"),
                                    "status": "started",
                                    "title": title,
                                }
                        if tool_name in {"task_cancel", "task_list", "task_result", "task_status"}:
                            for task_id, task_status in TASK_STATE_PATTERN.findall(text):
                                if task_id not in active_tasks:
                                    continue
                                if task_status in TERMINAL_TASK_STATES:
                                    active_tasks.pop(task_id, None)
                                else:
                                    active_tasks[task_id]["status"] = task_status
                            missing = re.search(r"No task (task-\d+)\.", text)
                            if missing and missing.group(1) in active_tasks:
                                active_tasks[missing.group(1)]["status"] = "lost"
                    elif entry_type == "custom_message" and entry.get("customType") == "background-task-result":
                        for task in (entry.get("details") or {}).get("tasks", []):
                            task_id = task.get("id")
                            task_status = task.get("status", "")
                            if task_id not in active_tasks:
                                continue
                            if task_status in TERMINAL_TASK_STATES:
                                active_tasks.pop(task_id, None)
                            elif task_status:
                                active_tasks[task_id]["status"] = task_status
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
        elif active_tasks and verdict == "settled":
            verdict = "settled+background"
        evidence = ";".join(
            f"{task_id}:{task['status']}:{task['title'][:80]}".replace("\t", " ").replace("\n", " ")
            for task_id, task in sorted(active_tasks.items(), key=lambda item: item[1]["started"])
        ) or "-"
        print(
            f"{session}\t{target}\t{state}\t{verdict}\t{timestamp}\t{len(active_tasks)}\t"
            f"{evidence}\t{workspace}\t{transcript or '-'}"
        )
PY
REMOTE
