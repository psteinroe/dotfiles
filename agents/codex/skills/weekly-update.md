---
name: weekly-update
description: Generate a two-week status update from PRs. Use when the user wants a summary of their work for the last two weeks. The user must specify the repository (owner/repo).
---

# Two-Week Update Skill

Generates a concise two-week update from merged and in-progress PRs for a given repository.

## Input

The user must provide the target repository as `owner/repo` (e.g. `acme/backend`). If not provided, ask for it.

## Workflow

1. **Resolve the User**
   - Run `gh api user -q '.login'` to get the GitHub username

2. **Calculate the Two-Week Range**
   - Use the most recent Friday as the end date:
     - Friday/Saturday/Sunday → this week's Friday
     - Monday/Tuesday/Wednesday/Thursday → previous week's Friday
   - Start date is 13 days before that Friday (Saturday), giving two full Saturday–Friday weeks.

   ```bash
   current_day=$(date +%u)  # 1=Monday, 7=Sunday
   days_since_friday=$(( (current_day + 2) % 7 ))

   range_end=$(date -v-"${days_since_friday}"d +%Y-%m-%d)
   range_start=$(date -v-"$((days_since_friday + 13))"d +%Y-%m-%d)
   ```

3. **Fetch Merged PRs**
   ```bash
   gh pr list --repo <owner/repo> --author <username> --state merged \
     --search "merged:${range_start}..${range_end}" \
     --json number,title,url,body,mergedAt --limit 100
   ```

4. **Fetch Open PRs with Activity**
   ```bash
   gh pr list --repo <owner/repo> --author <username> --state open \
     --json number,title,url,body,updatedAt --limit 50
   ```
   Filter to PRs updated within the same two-week range.

5. **Generate the Update**
   - Summarize each PR from its title and body — do not fetch individual commits
   - Group into Merged / In Progress sections
   - Write direct, factual bullet points — no fluff
   - Print to stdout (do NOT write a file unless asked)

## Output Format

```markdown
# Two Weeks: Jan 04 – Jan 17, 2026

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
- If no PRs found for the two-week range, say so clearly
