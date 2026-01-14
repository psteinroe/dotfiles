---
name: fix-ci
description: Fix CI failures. Use when the user wants to fix failing CI checks, GitHub Actions, or pipeline errors. Automatically checks CI status, fixes issues, commits, pushes, and waits for results. Asks for input when fixes are unclear.
---

# Fix CI Skill

This skill helps fix failing CI checks in GitHub repositories.

## Workflow

1. **Check CI Status**
   - Run `gh pr checks` or `gh run list` to see current CI status
   - If no PR exists, check the latest workflow runs on the current branch

2. **Analyze Failures**
   - For each failing check, run `gh run view <run-id> --log-failed` to get failure logs
   - Identify the root cause of each failure

3. **Fix Issues**
   - If the fix is straightforward (linting, formatting, type errors, test fixes):
     - Make the necessary code changes
     - Stage and commit with a descriptive message
     - Push the changes
   - If the fix is unclear or involves architectural decisions:
     - Explain the issue to the user
     - Present options if multiple approaches exist
     - Ask for permission before proceeding

4. **Wait and Verify**
   - After pushing, use `gh run watch --exit-status` to monitor the CI run
   - Exit status 0 means CI passed - report success
   - Non-zero exit status means CI failed - repeat from step 2

## Commands Reference

```bash
# Check PR status
gh pr checks

# List recent workflow runs
gh run list --branch $(git branch --show-current)

# View failed run logs
gh run view <run-id> --log-failed

# Watch a run in progress (exits non-zero if run fails)
gh run watch <run-id> --exit-status

# Re-run failed jobs
gh run rerun <run-id> --failed
```

## Guidelines

- Always read error logs carefully before making changes
- Prefer minimal, targeted fixes over large refactors
- If a test is flaky, mention it to the user rather than silently retrying
- Never skip tests or disable CI checks without explicit user approval
- If secrets or environment variables are missing, ask the user for guidance
