---
name: pr-writer
description: Create or refresh GitHub pull requests with direct gh commands. Use when opening a PR, updating an existing PR after material changes, or drafting a PR title/body.
---

# PR Writer

Create and update pull requests that are easy to review.

Agent guidance:
- Use direct `gh` commands for PR creation and updates.
- Do not commit, push, create, or update a PR unless the user asked for that side effect.

## Process

### Step 1: Verify Branch State

Detect the default branch and current branch:

```bash
gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'
git branch --show-current
git status --porcelain
```

Ensure:
- The current branch is not the default branch.
- All intended changes are committed before opening/updating the PR.
- If there are uncommitted changes, ask before staging/committing unless the user explicitly requested staging/committing as part of the task.
- The branch is pushed before creating a PR.

If the branch is stale, fetch the default branch before analyzing the diff:

```bash
git fetch origin BASE --quiet
```

### Step 2: Analyze the Current Diff

Review the commits and full PR diff against the detected base branch:

```bash
git log origin/BASE..HEAD --oneline
git diff origin/BASE...HEAD
```

Understand the dominant change and reviewer impact before writing copy. The PR title/body should describe the current diff, not the latest commit or the development history.

### Step 3: Check for an Existing PR

Check whether the current branch already has a PR:

```bash
gh pr view --json number,title,body,url,baseRefName,headRefName
```

If a PR exists:
- Treat the current title/body as inputs, not source of truth.
- Keep the title only if it still matches the dominant current change.
- Rewrite the body as one coherent description of the current PR.
- Refresh after material follow-up changes, especially scope changes, review-driven implementation changes, or added context that affects reviewer expectations.
- Skip trivial title/body updates for typo-only or rename-only diffs.

### Step 4: Write or Re-evaluate the PR Title

Use conventional-commit style:

```text
<type>(<scope>): <subject>
<type>: <subject>
```

Preferred types: `feat`, `fix`, `refactor`, `perf`, `docs`, `test`, `build`, `ci`, `chore`, `style`, `revert`.

Rules:
- Describe the dominant change, not the latest commit.
- Use the narrowest accurate type and scope.
- Keep it concise, ideally under 70 characters.
- No bracketed labels like `[codex]`, `[claude]`, `[ai]`, `[bot]`, or `[wip]`.
- No agent, tool, or automation attribution.
- No vague titles like `update`, `cleanup`, `misc`, `fix stuff`, or `address feedback`.
- No trailing period.

Examples:

```text
fix(api): paginate event list responses
refactor(auth): extract shared token validation
chore: update agent skill deployment docs
```

Use this update test: if a reviewer read only the title, would they form the right expectation about the current diff? If not, rewrite it.

### Step 5: Write or Update the PR Description

Write reviewer-facing prose, not a narrated diff.

Default structure:

```markdown
<1-3 sentence summary of what changed and why it matters. Keep this short.>

**<Optional Important Change>**

<1-2 sentences explaining behavior, implementation, risk, or review-relevant context.>

Refs <issue>
```

Rules:
- Lead with changed behavior; include implementation detail only when useful for review.
- Use 0-3 bold emphasis blocks for distinct reviewer-relevant changes.
- Use before/after fenced blocks only for changed contracts, output shapes, config, CLI output, payloads, permissions, or input formats.
- Add known issue references at the end; do not invent references.
- Omit headings like `Summary`, `Changes`, and `Test plan` unless the repository explicitly requires them.
- Do not include checkbox test plans, copied commit logs, file-by-file narration, or stale template scaffolding.
- Do not include customer/org names, user emails, support ticket contents, secrets, or PII. Describe the technical symptom and reference a sanitized ticket if available.

When updating an existing PR, rewrite the body as a fresh description of the current diff. Do not append a changelog of follow-up commits.

### Step 6: Create or Update the PR

For a new PR, create a ready-for-review PR by default, and use `--draft` only for WIP/early feedback or when the user asks for a draft.

Direct `gh` path:

```bash
gh pr create --title "<type>(<scope>): <subject>" --body "$(cat <<'EOF'
<description body here>
EOF
)"
```

Draft variant:

```bash
gh pr create --draft --title "<type>(<scope>): <subject>" --body "$(cat <<'EOF'
<description body here>
EOF
)"
```

For an existing PR, patch the title and body after re-evaluating both. Prefer the API patch path because it avoids `gh pr edit` project-field issues and is reliable for title/body-only updates.

```bash
gh api -X PATCH repos/{owner}/{repo}/pulls/PR_NUMBER \
  -f title='fix(api): preserve pagination cursor' \
  -f body="$(cat <<'EOF'
<updated description body here>
EOF
)"
```

## PR Description Examples

### Simple PR

```markdown
Hide advanced settings by default in the sidebar.

The section now starts collapsed so it does not consume space before users need it. Users who expand it keep the same persisted preference behavior as before.
```

### Feature PR

```markdown
Add Slack thread replies for deployment notifications.

When a deployment status changes, notifications now reply to the original Slack thread instead of creating a new channel message. This keeps related notifications grouped and reduces channel noise.

**Notification Threading**

Updated deployment notifications reuse the original message timestamp when one is available.

Refs ALERTS-123
```

### CLI or Schema Change PR

````markdown
Switch run logs to chunk-level JSONL records.

Run logs now write one versioned record per analyzed chunk instead of one large run-level record. This lets `runs follow` show findings as chunks complete while preserving durable run reconstruction at finalization.

**JSONL Shape**

Before, each line represented a full run result:

```jsonc
{
  "run": {...},
  "summary": "Found 2 issues",
  "findings": [...]
}
```

After, each line represents one chunk result:

```jsonc
{
  "schemaVersion": 1,
  "run": {...},
  "chunk": {
    "file": "src/api/auth.ts",
    "index": 1,
    "total": 2
  },
  "status": "ok",
  "findings": [...]
}
```

Refs ENG-456
````

### Refactor PR

```markdown
refactor(auth): extract shared validation
```

```markdown
Extract duplicate validation from the auth routes into a shared validator. There is no intended behavior change.

**Shared Validator**

The shared module keeps the existing endpoint behavior while giving future validation rules one place to live.
```

## Issue References

Reference issues only when known:

| Syntax | Effect |
|--------|--------|
| `Fixes #1234` | Closes a GitHub issue on merge |
| `Fixes ORG-123` | Closes an integrated tracker issue when configured |
| `Refs ORG-123` | Links without closing |
| `Refs https://linear.app/...` | Links an external issue URL |

## Guidelines

- **One PR per feature/fix** — do not bundle unrelated changes.
- **Keep PRs reviewable** — smaller PRs get faster, better reviews.
- **Explain the why** — code shows what; the description explains why and review risk.
- **Draft for WIP only** — create ready PRs by default; use drafts for early feedback.
- **Rewrite, don't append** — updated PRs should read like a fresh description of the current diff.
- **Re-evaluate the title on updates** — do not assume the existing title still fits after scope changes.
