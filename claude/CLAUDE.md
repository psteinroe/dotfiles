## Plan Mode

- Make the plan extremely concise. Sacrifice grammar for the sake of concision.
- At the end of each plan, give me a list of unresolved questions to answer, if any.

## Version Control

Detect repo type before using git commands:
- If `.jj/` exists → use jj (Jujutsu) with custom functions below
- Otherwise → use git

### Custom jj Functions (PREFER THESE)

| Function | Purpose | Use Instead Of |
|----------|---------|----------------|
| `jjclone <url>` | Clone repo with jj backend, create main workspace | `git clone` |
| `jjcreate <name>` | Create workspace + bookmark + install deps | `git checkout -b` |
| `jjcheckout <branch\|pr#>` | Checkout branch/PR into workspace | `git checkout`, `gh pr checkout` |
| `jjlist` | List all workspaces | `git worktree list` |
| `jjclean` | Remove merged/closed PR workspaces | manual cleanup |

### jj Aliases (for common operations)

| Alias | Command | git equivalent |
|-------|---------|----------------|
| `jjs` | `jj status` | `git status` |
| `jjd` | `jj diff` | `git diff` |
| `jjl` | `jj log -r "trunk()..@"` | `git log` (current stack) |
| `jjc "msg"` | `jj commit -m "msg"` | `git add . && git commit -m` |
| `jjf` | `jj git fetch --all-remotes` | `git fetch` |
| `jjr` | `jj rebase -d "trunk()"` | `git rebase main` |
| `jjn` | `jj next --edit` | navigate to next in stack |
| `jjp` | `jj prev --edit` | navigate to previous in stack |
| `jjnew` | `jj new` | start new change on top |
| `jjb <name>` | `jj bookmark create` | `git branch` |

### PR Workflow (jj-ryu aliases)

| Alias | Command | Purpose |
|-------|---------|---------|
| `jjstack` | `ryu` | view tracked stack |
| `jjtrack` | `ryu track` | track bookmarks for PR submission |
| `jjsubmit` | `ryu submit` | create/update stacked PRs |
| `jjsync` | `ryu sync` | sync after PR merge |

### Pushing Changes
After committing, push with: `jj git push`
For new bookmarks: `jj git push --bookmark <name>`

### Key Concepts
- jj auto-tracks all changes (no staging/git add needed)
- `jj commit` creates commit from working copy
- `jj describe -m "msg"` changes current commit message
- Bookmarks = branches (needed for pushing)
- `trunk()` auto-detects main/master/develop
