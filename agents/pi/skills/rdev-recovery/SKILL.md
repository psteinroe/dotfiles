---
name: rdev-recovery
description: Recover the rdev exe.dev machine after an OOM, disk exhaustion, freeze, failed SSH, or reboot. Use to reclaim safe remote disk space, restart the VM, verify remote Herdr and Pi restoration, identify interrupted Pi turns, send resource-gated continue prompts, or monitor CPU and memory while preserving a priority agent.
---

# rdev recovery

## 1. Establish control

This workflow controls live Herdr agents. Load the `herdr` skill, require `HERDR_ENV=1`, and follow the live `herdr --skill` instructions. Use direct SSH commands with an explicit remote session; a selected machine in the TUI does not retarget this pane's CLI.

Resolve this skill directory before invoking a script:

```bash
skill_dir="$HOME/.pi/agent/skills/rdev-recovery"
```

Run read-only triage first:

```bash
"$skill_dir/scripts/rdev-status.sh"
```

Completion criterion: determine whether the provider gateway, private SSH path, system, and saved Herdr sessions respond.

## Disk pressure branch

Inspect cleanup candidates first:

```bash
"$skill_dir/scripts/rdev-cleanup.sh" --dry-run
```

When `/` reaches 90% or the user reports disk exhaustion, run the conservative cleanup after receiving authorization:

```bash
"$skill_dir/scripts/rdev-cleanup.sh" --yes
```

The script stops after reaching 80% usage. It removes only reproducible caches, unused Docker build data/images/containers, package caches, and old journals. It preserves Docker volumes, Git worktrees, Pi transcripts, and active containers. Use `--force --yes` only when the user requests cleanup below the emergency threshold. If the script exits 3, inspect protected data and ask before deleting volumes or worktrees.

Completion criterion: `/` is at or below the target, or the remaining protected candidates and required authorization are reported.

## 2. Restart only with authorization

A user request to restart the machine is sufficient authorization. Otherwise ask first. Restart through the exe.dev control plane and wait for both SSH paths:

```bash
"$skill_dir/scripts/rdev-restart.sh" --yes
```

The script bypasses SSH multiplexing so a stale control socket cannot create a false result. It does not resize or delete the VM.

Completion criterion: `rdev-exe` and `rdev` both execute a fresh command after the provider reports the restart.

## 3. Verify restoration

Run status again, then inspect interrupted Pi transcripts:

```bash
"$skill_dir/scripts/rdev-status.sh"
"$skill_dir/scripts/rdev-interrupted.sh"
```

Herdr restores saved workspace topology and Pi session paths from `~/.config/herdr/sessions/<session>/session.json`. Pi transcripts live under `~/.pi/agent/sessions/**/*.jsonl`.

Treat transcript evidence as interrupted when its latest meaningful entry is a user message, tool call without a result, or tool result without a later assistant response. Also review every `settled+background` row: the script reconstructs successful `start_subagent` and `start_background_command` lifecycles and reports tasks without a later terminal result. These are review candidates, not automatic resume targets; stale watchers, superseded tasks, and deliberately abandoned work can remain unclosed in a transcript. Compare the recent conversation, current Herdr state, and live remote processes before sending `continue`. Preserve the report and disposition of each candidate in the recovery summary.

Completion criterion: every previously running remote Herdr session has a live server, every restored Pi process appears in `herdr agent list`, and each reported background candidate is either still live, safely resumed, or explicitly dismissed with evidence.

## 4. Resume by headroom

Order targets by user priority. Prompt the highest-priority target first. Pass the remaining targets in priority order to the resource gate:

```bash
"$skill_dir/scripts/rdev-resume.sh" \
  --session hellomateo \
  --protect wFY:p1 \
  --agent wFY:p1 \
  --agent hel14076-autoresponder \
  --agent hel14077-sendouts
```

The script sends `continue` without waiting for a full turn. It requires two safe samples before adding another agent, then guards the concurrent work. Defaults:

- memory available: at least 10 GiB before submission;
- load average: at most 10 on the eight-vCPU VM;
- CPU PSI `avg10`: at most 35%;
- memory PSI `avg10`: at most 2%;
- critical guard: 3 GiB available, load above 28 with CPU PSI above 80%, or memory PSI above 15%.

Use `--interrupt-on-critical` only when the user asked to keep the machine out of critical resource pressure. It interrupts the newest unprotected resumed turn first and never interrupts `--protect` targets.

For a long gate or guard, launch the script with the background-task workflow. Resource headroom—not another agent's completion—is the scheduling condition.

Completion criterion: every requested target accepted `continue`, or the script names the target withheld by the resource gate; the machine remains reachable throughout the guard interval.

## 5. Report

Report:

- disk usage before and after cleanup, reclaimed space, and any protected candidates left for approval;
- provider restart result and boot time;
- restored Herdr sessions and Pi count;
- targets that received `continue` and their current states;
- minimum observed memory headroom and peak load/pressure;
- any target interrupted or withheld by the guard;
- system, user-service, and Docker health failures.
