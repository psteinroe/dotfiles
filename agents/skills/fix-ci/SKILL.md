---
name: fix-ci
description: Fix CI failures. Use when the user wants to fix failing CI checks, GitHub Actions, or pipeline errors. Automatically checks CI status, fixes issues, commits, pushes, and waits for results. Asks for input when fixes are unclear.
---

# Fix CI Skill

This skill helps fix failing CI checks in GitHub repositories.

## Workflow

1. **Understand the Changes First**
   - Detect the base branch: `gh repo view --json defaultBranchRef -q '.defaultBranchRef.name'`
   - Run `git diff <base>...HEAD` or `git log --oneline <base>..HEAD` to see what changed
   - Read the modified files to understand the intent and context of the changes
   - This context is critical - CI failures often relate directly to the changes made

2. **Check CI Status**
   - Query compact fields: `gh pr checks --json name,state,bucket,link,workflow`
   - If no PR exists, query the current commit with `gh run list --commit "$(git rev-parse HEAD)" --json databaseId,status,conclusion,workflowName,url`

3. **Analyze Failures**
   - Resolve the failed run ID, then run `scripts/failed-run-summary.sh <run-id>` from this skill directory
   - The script keeps the complete failed log in a temporary file and returns only bounded diagnostic excerpts
   - Cross-reference failures with the changes from step 1 and identify each root cause

4. **Fix Issues**
   - If the fix is straightforward (linting, formatting, type errors, test fixes):
     - Make the necessary code changes
     - Stage and commit with a descriptive message
     - Push the changes
   - If the fix is unclear or involves architectural decisions:
     - Explain the issue to the user
     - Present options if multiple approaches exist
     - Ask for permission before proceeding

5. **Wait and Verify Quietly**
   - After pushing, run `scripts/wait-for-pr-checks.sh` from this skill directory with a Bash-tool timeout above its one-hour default deadline
   - For a branch without a PR, resolve the run ID and use `scripts/wait-for-run.sh <run-id>` instead
   - These scripts poll silently and emit one compact final result; keep working only when useful work remains, otherwise wait for that single result
   - Success means CI passed. Failure means repeat from step 3

## Commands Reference

```bash
# Check PR status without a live-refresh table
gh pr checks --json name,state,bucket,link,workflow

# List runs for the exact pushed commit
gh run list --commit "$(git rev-parse HEAD)" \
  --json databaseId,status,conclusion,workflowName,url

# Print bounded diagnostics and retain the complete failed log in /tmp
scripts/failed-run-summary.sh <run-id>

# Wait without streaming refresh snapshots into model context
scripts/wait-for-pr-checks.sh
scripts/wait-for-run.sh <run-id>

# Re-run failed jobs
gh run rerun <run-id> --failed
```

## Guidelines

- **Always understand the diff first** - don't blindly fix errors without knowing what changed
- Read bounded failure diagnostics first; inspect the retained full log only when the excerpt is insufficient
- Prefer minimal, targeted fixes over large refactors
- If a test is flaky, mention it to the user rather than silently retrying
- Never skip tests or disable CI checks without explicit user approval
- If secrets or environment variables are missing, ask the user for guidance
