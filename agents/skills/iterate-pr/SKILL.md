---
name: iterate-pr
description: Iterate a pull request through actionable review feedback and CI failures. Use when asked to fix CI, address PR feedback, get a PR green, or iterate until checks pass.
---

# Iterate PR

Drive one pull request to the next human gate or a clean state. Use at most three pushed fix attempts per invocation.

## Loop

1. **Establish the change**
   - Resolve the default branch and current PR.
   - If the branch has no PR, stop and ask whether to create one.
   - Inspect `git status`, `git log <base>..HEAD`, and the focused branch diff.
   - Record the current HEAD SHA and attempt count.

2. **Collect compact state**
   - Run `gh pr view --json number,url,isDraft,reviewDecision,headRefOid`.
   - Run `gh pr checks --json name,state,bucket,link,workflow`.
   - Run `scripts/review-summary.sh` from this skill directory for unresolved review threads.
   - A draft PR, approval requirement, or other human-only gate is terminal: report it instead of waiting.

3. **Choose one action**
   - Failed checks: resolve the failed run ID and run `scripts/failed-run-summary.sh <run-id>`.
   - Actionable review feedback: include the relevant thread, path, and requested behavior.
   - Pending automated checks with no actionable failure: start the quiet wait script explicitly with `bg_start`, title it `Wait for PR checks`, and use the pull request worktree as `working_dir`. Pass either the PR URL or its number; a number defaults to the repository at `working_dir`, or accepts an explicit `owner/repo` second argument. Do not poll with `bg_status`; its completion will resume the main agent.
   - No failures, actionable feedback, or automated checks pending: report completion.

4. **Delegate a bounded fix**
   - Call `worker` with the failure excerpt or review feedback, branch intent, relevant paths, constraints, and expected validation.
   - The worker edits and tests but does not commit or push.
   - Inspect the resulting diff and validation. Use `oracle` only when the diagnosis, architecture, or correctness remains uncertain.
   - Stop for user input when the fix changes product behavior, requires secrets, or has multiple consequential designs.

5. **Publish and wait**
   - Run the relevant local check, create one focused commit, and push.
   - Increment the pushed-attempt count.
   - Start `<skill-dir>/scripts/wait-for-pr-checks.sh <pr-number-or-url> [owner/repo]` with `bg_start` as described above.
   - When it completes, return to step 2 for the new HEAD.

## Stop conditions

Stop and report the current state when any condition holds:

- all automated checks pass and no actionable review feedback remains
- only a draft, approval, or other human gate remains
- the same failure recurs after a targeted fix
- three pushed fix attempts have been made
- the correct fix requires user judgment

## Output discipline

- Keep complete CI logs in the temporary files produced by `failed-run-summary.sh`; read more only when its bounded excerpt is insufficient.
- Treat flaky checks explicitly; do not silently rerun them.
- Preserve pre-existing test coverage when fixing CI; do not remove tests solely to make a failing check disappear.
- An explicit user request authorizes removing tests introduced by the current PR. Confirm they are additions in the focused base diff, remove only the requested tests, and continue without asking for permission again.
- Never disable checks, resolve review threads, merge, or approve on the user's behalf.
- Do not start duplicate background waits for the same HEAD.
- Treat the waiter's success as authoritative only after its built-in stable-check window; do not replace it with a one-shot `gh pr checks` result immediately after a push.
- When passing only a PR number, make sure `working_dir` is the pull request worktree; otherwise pass `owner/repo` explicitly.
