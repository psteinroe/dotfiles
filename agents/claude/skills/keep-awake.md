---
name: keep-awake
description: Keep the Mac screen awake during long-running tasks. Use this proactively when starting tasks that will take a while (builds, tests, deployments, large file operations). Prevents the screen from sleeping while Claude is working.
---

# Keep Awake Skill

Prevents the Mac from sleeping during long-running Claude sessions using the `coffee` command (a wrapper around macOS `caffeinate`).

## When to Use

Use this skill proactively when:
- Starting long builds or compilations
- Running extensive test suites
- Performing large file operations
- Any task that will take more than a few minutes

## Commands

```bash
# Start keeping awake indefinitely (until stopped)
coffee start

# Keep awake for a specific duration
coffee start 30m    # 30 minutes
coffee start 2h     # 2 hours

# Keep awake until a specific time
coffee until 17:30  # Until 5:30 PM

# Check current status
coffee status

# Stop keeping awake
coffee stop
```

## Workflow

1. **At start of long task**: Run `coffee start` or `coffee start <duration>`
2. **Monitor**: Use `coffee status` to verify it's active
3. **At end of task**: Run `coffee stop` to allow normal sleep behavior

## Guidelines

- Always stop the session when the task completes
- For tasks with known duration, prefer `coffee start <duration>` over indefinite
- If you're unsure how long a task will take, start indefinitely and stop when done
- The display stays on by default; use `-d` flag if display can sleep
