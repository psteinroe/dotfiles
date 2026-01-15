# Dotfiles

nix-darwin + home-manager config for macOS.

## Fresh Install

```bash
curl -fsSL https://raw.githubusercontent.com/psteinroe/dotfiles/main/scripts/bootstrap.sh | bash
```

## Manual Install

1. Install Xcode CLI: `xcode-select --install`
2. Install Nix: `curl -sSf -L https://install.determinate.systems/nix | sh`
3. Clone: `git clone https://github.com/psteinroe/dotfiles.git ~/Developer/dotfiles`
4. Build: `nix run nix-darwin -- switch --flake ~/Developer/dotfiles`

## Update

```bash
rebuild
```

---

## jj (Jujutsu) Workflow

Using jj with workspaces for stacked PRs via jj-ryu.

### Setup a New Repo

```bash
jjclone git@github.com:user/repo.git    # creates repo.jj/ with workspaces
```

### Common Aliases

| Alias | Command | Purpose |
|-------|---------|---------|
| `jjs` | `jj status` | Show status |
| `jjd` | `jj diff` | Show diff |
| `jjl` | `jj log -r "trunk()..@"` | Log current stack |
| `jjc "msg"` | `jj commit -m` | Commit changes |
| `jjf` | `jj git fetch` | Fetch from remote |
| `jjr` | `jj rebase -d trunk()` | Rebase onto main |

### Stack Navigation

| Alias | Command | Purpose |
|-------|---------|---------|
| `jjn` | `jj next --edit` | Go to next change |
| `jjp` | `jj prev --edit` | Go to previous change |
| `jjnew` | `jj new` | New change on top |
| `jjb name` | `jj bookmark create` | Create bookmark |

### Workspace Functions

| Function | Purpose |
|----------|---------|
| `jjcreate <name>` | Create workspace + bookmark + deps |
| `jjcheckout <branch\|pr#>` | Checkout branch/PR into workspace |
| `jjlist` | List workspaces |
| `jjclean` | Remove merged/closed PR workspaces |

### Stacked PR Workflow (jj-ryu)

```bash
# Create stack
jjnew && jjb feat-auth           # first change
jjc "Add auth"
jjnew && jjb feat-session        # stack on top
jjc "Add session"

# Submit PRs
jjtrack --all                    # track bookmarks
jjsubmit                         # create stacked PRs

# After merge
jjf && jjsync                    # sync remaining stack
```

---

## Ghostty Keybindings

Custom nvim-like keybindings.

### Split Navigation

| Action | Key |
|--------|-----|
| Go left | `Ctrl+H` |
| Go down | `Ctrl+J` |
| Go up | `Ctrl+K` |
| Go right | `Ctrl+L` |

### Split Management

| Action | Key |
|--------|-----|
| New split right | `Cmd+D` |
| New split down | `Cmd+Shift+D` |
| Toggle zoom | `Cmd+Shift+Enter` |
| Equalize | `Alt+Shift+=` |
| Close | `Cmd+W` |

### Split Resize

| Action | Key |
|--------|-----|
| Resize left | `Cmd+Ctrl+H` |
| Resize down | `Cmd+Ctrl+J` |
| Resize up | `Cmd+Ctrl+K` |
| Resize right | `Cmd+Ctrl+L` |

### Tabs

| Action | Key |
|--------|-----|
| New tab | `Cmd+T` |
| Prev tab | `Cmd+Shift+[` |
| Next tab | `Cmd+Shift+]` |
| Go to tab 1-9 | `Cmd+1-9` |

---

## License

MIT
