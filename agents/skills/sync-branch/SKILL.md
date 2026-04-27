---
name: sync-branch
description: Sync current branch with main. Use when the user wants to update their feature branch with the latest changes from the main branch. Fetches, rebases, and handles conflicts.
---

# Sync Branch Skill

This skill brings the current branch up to date with the main branch using rebase.

## Workflow

1. **Detect Main Branch**
   - Run `gh repo view --json defaultBranchRef -q '.defaultBranchRef.name'` to get the default branch
   - Don't assume it's called "main" - could be "master", "develop", etc.

2. **Understand Context First**
   - Run `git log --oneline <main>..HEAD` to see commits on this branch
   - Run `git diff <main>...HEAD --stat` to see what files changed
   - Read key modified files to understand the intent of the changes
   - This context is critical for resolving conflicts correctly later

3. **Check Current State**
   - Run `git status` to check for uncommitted changes
   - If there are uncommitted changes, ask user whether to stash or commit them first
   - Run `git branch --show-current` to confirm current branch

4. **Fetch Latest**
   - Run `git fetch origin <main-branch>` to get latest changes

5. **Rebase onto Main**
   - Run `git rebase origin/<main-branch>`
   - If rebase succeeds with no conflicts, report success

6. **Handle Conflicts (if any)**
   - If conflicts occur, list the conflicted files
   - For each conflict:
     - Use context from step 2 to understand the intent of your changes
     - Compare with incoming changes from main
     - Resolve preserving the intent of both sides
     - Run `git add <file>` after resolving
   - After all conflicts resolved, run `git rebase --continue`
   - Repeat until rebase completes

7. **Push Updated Branch**
   - Ask user if they want to force push: `git push --force-with-lease`
   - `--force-with-lease` is safer than `--force` as it checks for upstream changes

## Commands Reference

```bash
# Detect main branch
gh repo view --json defaultBranchRef -q '.defaultBranchRef.name'

# Check current state
git status
git branch --show-current

# Fetch and rebase
git fetch origin <main>
git rebase origin/<main>

# During conflicts
git status                  # See conflicted files
git diff                    # See conflict details
git add <file>              # Mark as resolved
git rebase --continue       # Continue rebase
git rebase --abort          # Abort if needed

# Push with force
git push --force-with-lease
```

## Guidelines

- **Always understand context first** - read the branch's changes before rebasing
- **Always use rebase** - keeps history clean and linear
- **Never force push without asking** - it rewrites history
- Use `--force-with-lease` instead of `--force` for safety
- If conflicts are complex, explain them to the user before resolving
- Stash or commit uncommitted changes before rebasing
- If rebase gets messy, offer to abort and try a different approach
