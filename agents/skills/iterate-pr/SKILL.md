---
name: iterate-pr
description: Iterate or merge a pull request through actionable review feedback and CI failures. Use when asked to fix CI, address PR feedback, get a PR green, merge after checks pass, or explicitly bypass review approval.
---

# Iterate PR

Drive one pull request to a clean state or, when explicitly authorized, merge it. Use at most three pushed fix attempts per invocation.

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
   - A draft PR is terminal. An approval requirement or other review-only gate is terminal unless the user explicitly authorized merging this PR and bypassing reviews.

3. **Choose one action**
   - Failed checks: resolve the failed run ID and run `scripts/failed-run-summary.sh <run-id>`.
   - Actionable review feedback: include the relevant thread, path, and requested behavior, unless the user explicitly authorized skipping reviews for the merge.
   - Pending automated checks with no actionable failure: start the quiet wait script explicitly with `bg_start`, title it `Wait for PR checks`, and use the pull request worktree as `working_dir`. Pass either the PR URL or its number; a number defaults to the repository at `working_dir`, or accepts an explicit `owner/repo` second argument. Do not poll with `bg_status`; its completion will resume the main agent.
   - No failures or automated checks pending: merge when explicitly authorized; otherwise report completion or actionable feedback.

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

6. **Merge only when explicitly authorized**
   - Treat `merge this PR` as authorization to merge the identified current PR after automated checks pass. Treat `skip reviews` or `bypass review` as separate authorization to ignore review approval and actionable review feedback for that merge.
   - Immediately before merging, re-resolve the PR URL and number, verify the expected head SHA, and confirm the stable watcher found no failed or pending automated checks.
   - Use the user's requested merge method; otherwise follow the repository convention. If review approval is the remaining blocker and bypass was explicitly authorized, use GitHub's admin merge bypass rather than approving the PR or resolving review threads.
   - Do not ask for merge or review-bypass permission again once the user supplied it for this PR. Verify and report the resulting `MERGED` state.

## Stop conditions

Stop and report the current state when any condition holds:

- all automated checks pass and no actionable review feedback remains, unless an authorized merge remains to perform
- only a draft remains, or only an approval/review gate remains and the user did not explicitly authorize bypassing reviews for the merge
- the same failure recurs after a targeted fix
- three pushed fix attempts have been made
- the correct fix requires user judgment

## Output discipline

- Keep complete CI logs in the temporary files produced by `failed-run-summary.sh`; read more only when its bounded excerpt is insufficient.
- Treat flaky checks explicitly; do not silently rerun them.
- Preserve pre-existing test coverage when fixing CI; do not remove tests solely to make a failing check disappear.
- An explicit user request authorizes removing tests introduced by the current PR. Confirm they are additions in the focused base diff, remove only the requested tests, and continue without asking for permission again.
- Never disable automated checks, approve the PR, or resolve review threads. An explicitly authorized review bypass must use the merge mechanism without mutating review state.
- Do not start duplicate background waits for the same HEAD.
- Treat the waiter's success as authoritative only after its built-in stable-check window; do not replace it with a one-shot `gh pr checks` result immediately after a push.
- When passing only a PR number, make sure `working_dir` is the pull request worktree; otherwise pass `owner/repo` explicitly.
