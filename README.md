# Dotfiles

nix-darwin + home-manager config for macOS.

## Fresh Install

```bash
curl -fsSL https://raw.githubusercontent.com/psteinroe/dotfiles/main/bootstrap.sh | bash
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

## Tailscale (macOS)

- GUI app is installed via Homebrew cask: `tailscale-app`
- CLI is installed via Nix package: `tailscale`
- First-time setup requires manual approval in macOS:
  1. `open -a Tailscale`
  2. Approve extension in `System Settings -> Privacy & Security`
  3. Accept VPN/network configuration prompt
- Verify with:

```bash
tailscale status
systemextensionsctl list | rg -i tailscale
```

## OpenCode Shared Server (Mac + Phone)

Use one shared OpenCode web backend and attach from each project locally.
`oc` lazy-starts the backend if it is not running.

### One-time setup

```bash
set-keychain-environment-variable OPENCODE_SERVER_PASSWORD
rebuild
```

### Attach per project (local CLI, lazy start)

```bash
cd /path/to/project
oc              # copen: attach with --dir "$PWD" (auto-starts ocweb if needed)
```

### Manual server controls

```bash
ocweb start      # starts `opencode web` in background on 0.0.0.0:4096
ocweb status
ocweb url        # prints localhost + Tailscale URL
ocweb logs
ocweb stop
```

Optional tailnet-only passwordless mode:

```bash
export OPENCODE_WEB_HOSTNAME="$(tailscale ip -4 | awk 'NR==1{print $1}')"
ocweb start
```

This is allowed only when hostname is your exact local Tailscale IPv4 (100.x.x.x).
In this mode, `ocweb` disables OpenCode basic auth by default even if
`OPENCODE_SERVER_PASSWORD` is configured.

To force auth on Tailscale host:

```bash
export OPENCODE_WEB_TAILSCALE_REQUIRE_PASSWORD=1
ocweb restart
```

### Continue on phone

1. Connect phone + Mac to Tailscale.
2. Open the URL from `ocweb url` on your phone.
3. Continue the same sessions from web while still attaching locally with `oc`.

---

## Git Worktree Workflow

Using bare git repos with worktrees for parallel development + git-town for stacked PRs.

### Setup a New Repo

```bash
wtclone git@github.com:user/repo.git    # creates repo.git/ with main/ worktree
```

### Worktree Functions

| Function | Purpose |
|----------|---------|
| `wtclone <url>` | Clone as bare repo with main worktree |
| `wtcreate <name>` | Create new branch worktree |
| `wtcheckout <branch\|pr#>` | Checkout branch/PR into worktree |
| `wtlist` | List worktrees |
| `wtclean` | Remove merged/closed PR worktrees |

### git-town Commands (Stacked PRs)

| Alias | Command | Purpose |
|-------|---------|---------|
| `gts` | `git town sync` | Sync all branches |
| `gth` | `git town hack` | Create feature branch |
| `gtp` | `git town propose` | Create PR |
| `gtsh` | `git town ship` | Merge shipped PR |

### Full Workflow

```bash
# 1. Clone repo with bare setup
wtclone git@github.com:user/repo.git
cd repo.git/main

# 2. Create feature branch
wtcreate my-feature
# or from root: wtcreate my-feature

# 3. Make changes and commit normally
git add -A
git commit -m "Add feature"

# 4. Create PR
gtp                              # opens PR in browser

# 5. After merge, sync and cleanup
gts                              # sync all branches
wtclean                          # remove merged worktrees
```

### Review a PR or Branch

```bash
wtcheckout 123                   # checkout PR #123
wtcheckout feat-other            # checkout branch
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
