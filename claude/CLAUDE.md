## Plan Mode

- Make the plan extremely concise. Sacrifice grammar for the sake of concision.
- At the end of each plan, give me a list of unresolved questions to answer, if any.

## Working with git

- Never mention Claude Code in commit messages or pull request descriptions
- Always prefer rebase over merge to keep history clean
- Use `gh repo view --json defaultBranchRef -q '.defaultBranchRef.name'` to detect the main branch (not always "main")

## Version Control

Use git with worktrees for parallel development. Use git-town for stacked PRs.

### Worktree Functions

| Function | Purpose | Use Instead Of |
|----------|---------|----------------|
| `wtclone <url>` | Clone as bare repo with main worktree | `git clone` |
| `wtcreate <name>` | Create new branch worktree | `git checkout -b` |
| `wtcheckout <branch\|pr#>` | Checkout existing branch/PR | `git checkout`, `gh pr checkout` |
| `wtlist` | List worktrees | `git worktree list` |
| `wtclean` | Clean up merged/closed PR worktrees | manual cleanup |

### Git Aliases

| Alias | Purpose |
|-------|---------|
| `gc [msg]` | Commit with message (default: "progress") |
| `gca [msg]` | Add all + commit (default: "progress") |
| `gp` | Push |
| `gl` | Pull |
| `gs` | Status |
| `gt` | git-town |

### Quick PR Function

| Command | Purpose |
|---------|---------|
| `gpr` | Commit "initial" + push + create PR on **current branch** |
| `gpr -n` | Create **new random branch** + commit + push + create PR |

### Typical PR Workflow
1. `wtclone <url>` - Clone repo with bare setup
2. `wtcreate feat/xxx` - Create worktree for feature
3. Make changes, commit with `gc` or `gca`
4. `gpr` - Push and create PR
5. After merge: `gt sync` to sync, `wtclean` to cleanup
