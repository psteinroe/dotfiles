# Dotfiles

Cross-platform Nix + Home Manager dev environment.

- macOS: `nix-darwin` + Home Manager
- Linux remotes: standalone Home Manager

## Fresh Install: macOS

```bash
curl -fsSL https://raw.githubusercontent.com/psteinroe/dotfiles/main/bootstrap.sh | bash
```

## Fresh Install: Linux Remote

```bash
curl -fsSL https://raw.githubusercontent.com/psteinroe/dotfiles/main/bootstrap-remote.sh | bash
```

The default Linux target is:

```text
homeConfigurations."psteinroe@linux-x86_64"
```

## Manual Install: macOS

1. Install Xcode CLI: `xcode-select --install`
2. Install Determinate Nix: `curl -sSf -L https://install.determinate.systems/nix | sh -s -- install`
3. Clone: `git clone https://github.com/psteinroe/dotfiles.git ~/Developer/dotfiles`
4. Build: `nix run nix-darwin -- switch --flake ~/Developer/dotfiles#psteinroe`

## Manual Install: Linux Remote

1. Install Determinate Nix:
   `curl -sSf -L https://install.determinate.systems/nix | sh -s -- install linux --no-confirm`
2. Clone: `git clone https://github.com/psteinroe/dotfiles.git ~/Developer/dotfiles`
3. Build: `nix run nixpkgs#home-manager -- switch --flake ~/Developer/dotfiles#psteinroe@linux-x86_64`

## Update

```bash
rebuild
```

## Remote Dev Workflow

The local SSH alias `rdev` points at the generic remote VM. Override per command with `RDEV_HOST` if needed.

```bash
ssh rdev
rrebuild
rwtclone https://github.com/org/app.git app
rwtcreate app feature-x
rdevstack app feature-x feature-child  # stack child branch on existing parent, attach tmux
rwtcheckout app 123
rwtlist app
rdev app feature-x       # remote tmux shell/nvim
rpi app feature-x        # local Pi UI, remote SSH-backed tools
rpicodexauth             # copy local Pi Codex subscription auth to the remote
```

`rdev` upserts the requested remote worktree: if `~/Developer/<repo>.git/<branch>` does not exist, it creates/checks out the worktree first, then attaches tmux. Use `rdevstack <repo> <parent> <branch>` when the new branch should be created from an existing parent branch. Closing the local Ghostty tab detaches SSH but leaves remote zsh/Neovim running.

`rpi` performs the same remote worktree upsert but does **not** attach tmux. It starts Pi locally from a shadow cwd under `~/.cache/pi-remote/...` and passes `--remote-ssh/--remote-cwd` to the Pi `remote-ssh` extension, so Pi input stays local while `read`, `write`, `edit`, `bash`, `ls`, `find`, `grep`, and `!` commands execute on the remote VM. Use `rdev` only when you need a real remote terminal, tmux, or Neovim.

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

Using bare git repos with worktrees for parallel development.

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
| `wtensure <branch\|pr#>` | Upsert a worktree and cd into it without tmux (used by `rpi`/`wttmux`) |

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
gpr                              # quick commit/push/create flow

# 5. After merge, cleanup
wtclean                          # remove merged worktrees
```

### Review a PR or Branch

```bash
wtcheckout 123                   # checkout PR #123
wtcheckout feat-other            # checkout branch
```

---

## Terminal GitHub Workflow

`tuicr` is the terminal code-review UI for reviewing local changes like a PR.

| Command | Purpose |
|---------|---------|
| `review` | Open `tuicr` for the current repository |
| `gpd [pr]` | `gh pr diff [pr] --color=never \| diffnav`; pipe a PR diff into diffnav |
| `lazygit` | Open the terminal Git UI |
| `wtcheckout <branch\|pr#>` | Checkout a branch/PR into a worktree |
| `gpr [-a] [-n] [-e] [-d] [-f issue]` | Commit/push/create a PR with generated copy, or open the GitHub editor with `-e` |
| `/pr [--all|-a] [--draft] [--fixes issue] [--refs issue]` | In Pi, create or refresh a PR for the current branch using the `pr-writer` skill; `--all`/`-a` stages and commits first |

`diffnav` is configured as the pager for `git diff`; other git commands continue to use `delta` through `core.pager`.

---

## Ghostty

Config: `ghostty.conf` → `~/.config/ghostty/config`.

Ghostty uses native macOS tabs, is routed by AeroSpace to workspace `1`, and stays floating.

### Keybindings

| Area | Action | Key |
|------|--------|-----|
| Splits | Focus left/down/up/right | `Ctrl+H/J/K/L` |
| Splits | Resize left/down/up/right | `Cmd+Ctrl+H/J/K/L` |
| Splits | New split right / down | `Cmd+D` / `Cmd+Shift+D` |
| Splits | Toggle zoom / equalize / close | `Cmd+Shift+Enter` / `Alt+Shift+=` / `Cmd+W` |
| Tabs | New tab / window | `Cmd+T` / `Cmd+N` |
| Tabs | Switch tab | `Cmd+1` … `Cmd+9` |
| Tabs | Previous / next tab | `Cmd+Shift+[` / `Cmd+Shift+]` |
| Windows | Previous / next window | `Cmd+Shift+H/L` |
| Ghostty | Command palette | `Cmd+Shift+P` |
| Scrollback | Half page up/down | `Cmd+Alt+U/D` |
| Scrollback | Page up/down | `Cmd+Alt+B/F` |
| Scrollback | Line up/down | `Cmd+Alt+Y/E` |
| Scrollback | Top / bottom | `Cmd+Alt+G` / `Cmd+Alt+Shift+G` |
| Selection | Select all | `Cmd+A` |
| Selection | Extend existing selection | `Cmd+Alt+Shift+H/J/K/L` or `Cmd+Alt+Shift+B/F` |

`Cmd+Alt` is used for scrollback instead of raw `Ctrl` so shells, Neovim, and Ghostty defaults still work. Selection keybindings only adjust an existing selection; Ghostty does not provide a full Vim visual mode.

---

## Neovim Pi

Pi opens inside a floating Neovim terminal via ToggleTerm and uses `cpi`, which first tries `pi --continue` and falls back to a new session.

| Action | Key |
|--------|-----|
| Toggle Pi | `Ctrl+A` |
| Toggle Pi alternative | `<leader>ap` |

Other Neovim agent integrations are disabled/removed; `Ctrl+A` opens Pi directly instead of showing an agent picker.

---

## AeroSpace

The Dock is configured to auto-hide via nix-darwin so AeroSpace fullscreen can use the bottom of the screen.

- Installed via Homebrew cask: `nikitabobko/tap/aerospace`
- Config is tracked in repo at `aerospace.toml`
- Nix symlinks it to `~/.config/aerospace/aerospace.toml`
- Setup is optimized for one monitor with six persistent daily workspaces plus a non-persistent overflow workspace.

Apply changes:

```bash
rebuild
```

Useful runtime commands:

```bash
aerospace reload-config
aerospace list-workspaces --all
aerospace list-windows --all
```

### Daily workspace layout

| Workspace | Shortcut | App / purpose |
|-----------|----------|---------------|
| `1` | `Alt+1` | Ghostty / terminal |
| `2` | `Alt+2` | Browser: Chrome or Safari |
| `3` | `Alt+3` | Apple Notes |
| `4` | `Alt+4` | Slack |
| `5` | `Alt+5` | Linear |
| `6` | `Alt+6` | Spotify |
| `7` | `Alt+7` | Overflow for unpinned apps; non-persistent and floating |

AeroSpace auto-moves pinned apps to their assigned workspace when their windows are detected. `bin/aerospace-pinned-app-guard` also re-applies those pinned workspace assignments on focus/workspace changes, covering macOS restore/hide cases where `on-window-detected` does not fire. Any other app opens on workspace `7`, which is not persistent, floats its windows, and disappears when empty.

Workspaces `1`–`6` are auto-normalized with `bin/aerospace-grid-2col` when focused: the first two windows stay side-by-side and extra windows start below them, avoiding ultra-thin columns. Workspace `7` is skipped so crowded overflow windows are not squeezed into the tiled grid.

Ghostty is special-cased: AeroSpace always routes Ghostty to workspace `1` and keeps it floating. Native tabs remain enabled; use Ghostty's command palette (`Cmd+Shift+P`) to search/switch tabs. macOS hide shortcuts (`Cmd+H`, `Cmd+Alt+H`) are disabled because hidden/revealed windows can bypass detection.

### Core usage

| Action | Shortcut |
|--------|----------|
| Open Ghostty | `Alt+Enter` |
| Switch workspace | `Alt+1` … `Alt+7` |
| Move focused window to workspace | `Alt+Shift+1` … `Alt+Shift+7` |
| Jump back to previous workspace | `Alt+Tab` |
| Focus adjacent window | `Alt+H/J/K/L` |
| Move focused window | `Alt+Shift+H/J/K/L` |
| Resize smartly | `Alt+-` / `Alt+=` |
| Enter resize mode | `Alt+R`, then `H/J/K/L`, `Esc` to leave |
| Toggle AeroSpace fullscreen without outer gaps | `Alt+F` |
| Toggle floating/tiling | `Alt+Shift+F` |
| Re-apply two-column workspace layout | `Alt+G` |
| Enter service mode | `Alt+;` |

Service mode shortcuts after `Alt+;`:

| Action | Key |
|--------|-----|
| Reload config | `Esc` |
| Flatten/reset workspace layout | `R` |
| Toggle floating/tiling | `F` |
| Close all windows except current | `Backspace` |
| Join with adjacent window | `H/J/K/L` |

Important: AeroSpace fails if both `~/.aerospace.toml` and `~/.config/aerospace/aerospace.toml` exist. Keep only the XDG one.

---

## License

MIT
