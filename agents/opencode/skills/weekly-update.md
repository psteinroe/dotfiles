---
name: weekly-update
description: Generate a weekly status update from PRs. Use when the user wants a summary of their work for the past week. The user must specify the repository (owner/repo).
---

# Weekly Update Skill

Generates a concise weekly update from merged and in-progress PRs for a given repository.

## Input

The user must provide the target repository as `owner/repo` (e.g. `acme/backend`). If not provided, ask for it.

## Workflow

1. **Resolve the User**
   - Run `gh api user -q '.login'` to get the GitHub username

2. **Calculate the Week Range**
   - If today is Friday/Saturday/Sunday, report on THIS week (Saturday–Friday)
   - If today is Monday–Thursday, report on the PREVIOUS week (Saturday–Friday)

   ```bash
   current_day=$(date +%u)  # 1=Monday, 7=Sunday
   if [ $current_day -ge 5 ]; then
     week_saturday=$(date -v-$(($(date +%u) % 7))d +%Y-%m-%d)
     week_friday=$(date -v+$((6 - $(date +%u) % 7))d +%Y-%m-%d)
   else
     week_saturday=$(date -v-$(($(date +%u) % 7 + 7))d +%Y-%m-%d)
     week_friday=$(date -v-$(($(date +%u) % 7 + 1))d +%Y-%m-%d)
   fi
   ```

3. **Fetch Merged PRs**
   ```bash
   gh pr list --repo <owner/repo> --author <username> --state merged \
     --search "merged:${week_saturday}..${week_friday}" \
     --json number,title,url,body,mergedAt --limit 100
   ```

4. **Fetch Open PRs with Activity**
   ```bash
   gh pr list --repo <owner/repo> --author <username> --state open \
     --json number,title,url,body,updatedAt --limit 50
   ```
   Filter to PRs updated within the week range.

5. **Generate the Update**
   - Summarize each PR from its title and body — do not fetch individual commits
   - Group into Merged / In Progress sections
   - Write direct, factual bullet points — no fluff
   - Print to stdout (do NOT write a file unless asked)

## Output Format

```markdown
# Week: Jan 13 – Jan 17, 2026

## Merged

**Add user settings page** — [#1234](https://github.com/owner/repo/pull/1234)
- Implemented preferences form with validation
- Added dark mode toggle persistence

## In Progress

**Migrate to new API v3** — [#1240](https://github.com/owner/repo/pull/1240) (draft)
- Significant progress on endpoint migration, not yet merged
```

## Guidelines

- Target audience: team leads and management — focus on clarity, not technical details
- Keep descriptions direct and factual
- No cliche, flowery, or marketing language
- If no PRs found for the week, say so clearly
