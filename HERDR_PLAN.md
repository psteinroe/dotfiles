# Herdr remote-dev plan

## Goal

Replace most remote tmux-centric project switching with Herdr while preserving the existing dotfiles workflow:

- local macOS workstation managed by `nix-darwin` + Home Manager
- remote Linux dev host reachable as SSH alias `rdev`
- remote bare-repo worktree layout under `~/Developer/<repo>.git/<worktree>`
- existing `wt*` and `rwt*` helper semantics
- Pi/Claude/Codex/OpenCode agent configs managed declaratively by this repo

Target shape:

```text
rdev remote host
├── Herdr session: hellomateo
│   ├── workspace: main        -> /home/psteinroe/Developer/hellomateo.git/main
│   ├── workspace: feature-x   -> /home/psteinroe/Developer/hellomateo.git/feature-x
│   └── workspace: pr-123      -> /home/psteinroe/Developer/hellomateo.git/pr-123
├── Herdr session: postgres-language-server
│   ├── workspace: main
│   └── workspace: parser-refactor
└── Herdr session: dotfiles
    └── workspace: main
```

Core mapping:

- **Herdr named session = project/repo**
- **Herdr workspace = Git worktree**
- **Herdr panes = shells, agents, servers, tests, logs inside that worktree**
- **`rdev`/tmux remains as fallback during migration**

Connectivity modes:

- **Normal laptop mode:** `herdr --remote rdev --session <repo>` for Herdr's local thin client, local keybindings, and local clipboard/image-paste bridging.
- **Roaming/mobile/bad-network mode:** `mosh rdev -- herdr --session <repo>` for resilient terminal attach when switching networks or sleeping/waking a laptop.
- **Fallback mode:** existing `rdev` tmux helpers stay available while the Herdr workflow matures.

## Current repo facts this plan builds on

- `rdev`/`rdev-host` currently SSH to `rdev`, sudo into remote user `psteinroe`, ensure a remote worktree, then attach a remote tmux session.
- `rpi` currently keeps the Pi UI local but delegates tools to the remote cwd through Pi's remote-SSH extension.
- Remote worktrees are stored under:

  ```text
  /home/psteinroe/Developer/<repo>.git/<worktree>
  ```

- `wtensure` already knows how to:
  - resolve branch names, PR numbers, and worktree names
  - create missing worktrees
  - pull clean existing branches
  - print the resolved worktree path with `WTENSURE_PRINT_PATH=1`
- `wtclean` and `wtforceclean` already know how to remove worktrees safely and kill matching tmux sessions.
- Mosh can improve the remote terminal experience for unstable networks, but it is not a drop-in transport for Herdr's `--remote` thin-client protocol. It should be used as an alternate attach path that runs the Herdr TUI on the remote host.

## Mosh capabilities and constraints relevant to this setup

Mosh (`mobile-shell/mosh`) is a remote terminal application that logs in via SSH, starts `mosh-server` remotely, then carries the terminal session over encrypted UDP.

Useful properties:

- survives intermittent connectivity, laptop sleep/wake, and IP changes
- roams across Wi-Fi/cellular/Tailscale path changes
- provides predictive local echo for lower perceived latency
- handles packet loss better than SSH for interactive terminals
- has no daemon and no privileged code; server processes are per connection
- works with normal SSH authentication and SSH config aliases
- can run a remote command, e.g. `mosh host -- herdr --session repo`

Important constraints:

- Mosh requires `mosh-client` locally and `mosh-server` remotely.
- Mosh requires UDP reachability from client to server. By default it uses UDP ports in the `60000-61000` range, or a fixed port/range with `-p`.
- Mosh is only for interactive terminal sessions. It does not support SSH port forwarding or non-interactive SSH-style command execution.
- Mosh is not a byte-stream transport, so it cannot directly replace the SSH bridge used by `herdr --remote`.
- Running Herdr over Mosh means the Herdr client is remote, not local. This gives roaming robustness but loses Herdr thin-client niceties such as local clipboard image-paste bridging and local-client audio behavior.
- Mosh synchronizes visible terminal state, not outer terminal scrollback. Herdr's own pane scrollback still exists inside the Herdr session, but the host terminal's scrollback should not be treated as complete.
- Mosh requires UTF-8 locales on both sides.

Recommended use:

- Keep `rherdr` as the default for normal local-laptop work.
- Add `rmherdr` / `rherdr --mosh` for roaming, phone, train, spotty Wi-Fi, or long-lived interactive monitoring.
- Prefer using Mosh over Tailscale if the public/exe.dev path does not expose UDP.

## Herdr capabilities relevant to this setup

From Herdr docs and examples:

- `herdr --remote rdev --session <name>` attaches a local thin client to an independent named session on the remote host.
- Named sessions have their own panes, tabs, workspaces, sockets, and runtime state, but share the same global Herdr config.
- Herdr has CLI commands for:
  - sessions: `herdr session list`, `herdr session attach`, `herdr session stop`
  - workspaces: `herdr workspace list/create/focus/close/rename`
  - worktrees: `herdr worktree list/create/open/remove`
  - panes: `herdr pane split/run/read/close/rename`
  - agents: `herdr agent list/read/wait/attach/start`
- Herdr integrations exist for Pi, Claude Code, Codex, and OpenCode, matching the agents already installed by this repo.
- Herdr plugins are a recently released v1 surface with:
  - `herdr-plugin.toml`
  - declared `[[actions]]`
  - declared `[[events]]`
  - declared `[[panes]]`
  - declared `[[link_handlers]]`
  - optional install-time `[[build]]`
  - runtime env such as `HERDR_BIN_PATH`, `HERDR_PLUGIN_CONTEXT_JSON`, `HERDR_WORKSPACE_ID`, `HERDR_TAB_ID`, `HERDR_PANE_ID`, `HERDR_PLUGIN_CONFIG_DIR`, `HERDR_PLUGIN_STATE_DIR`
- Plugins are not sandboxed; they are ordinary user code. Since this plugin would live in trusted dotfiles, that is acceptable.

## Plugin-system decision

Use plain zsh wrappers for the first migration, install `paulbkim-dev/vim-herdr-navigation` immediately for Neovim/Herdr pane navigation, then add a small local Herdr plugin for project/worktree actions once the CLI behavior is stable.

Reasoning:

- `rherdr <repo> [worktree]` starts outside Herdr, before a session is attached. This is naturally a shell wrapper, not a Herdr plugin action.
- `wtclean`, `wtforceclean`, `rwtclean`, and `rwtforceclean` are existing shell workflows and should remain usable outside Herdr.
- `hsyncworktrees` and `hwtcreate` can start as zsh functions because they need tight integration with existing `wtensure`, `wtcreate`, and repo layout conventions.
- `paulbkim-dev/vim-herdr-navigation` is a good fit for the immediate navigation problem:
  - Herdr side: plugin actions `left/down/up/right` call `navigate.sh`.
  - The script checks the focused pane's foreground process with `herdr pane process-info` and `jq`.
  - If the pane is Vim/Neovim, it forwards `ctrl+h/j/k/l` into that pane with `herdr pane send-keys`.
  - Otherwise it moves Herdr focus with `herdr pane focus --direction`.
  - Editor side: `editor/nvim.lua` maps `<C-h/j/k/l>` to move Neovim windows first, then cross into Herdr at split edges via `$HERDR_PANE_ID`.
- A custom plugin is still useful later for project/worktree actions inside Herdr:
  - sync workspaces from Git worktrees
  - create a worktree from current project session
  - bootstrap panes for a workspace
  - maybe preview GitHub PR links later

Recommended phased plugin split:

1. **Phase 1: Shell-first + navigation plugin**
   - implement `rherdr`, `hsyncworktrees`, `hwtcreate`, and Herdr cleanup hooks as zsh functions
   - install/link `paulbkim-dev/vim-herdr-navigation` for seamless `Ctrl-h/j/k/l` navigation
2. **Phase 2: Local trusted project plugin**
   - add `herdr/plugins/worktree-sync/herdr-plugin.toml`
   - expose Herdr actions that call the same shell helpers
   - link the plugin from Home Manager activation with `herdr plugin link`
3. **Phase 3: Optional plugin polish**
   - keybindings for sync/create/bootstrap
   - optional event hook for Herdr-native `worktree.created` events if using Herdr's own `worktree create`
   - optional pane entrypoint for a worktree manager UI

## Files to add

### `herdr/config.toml`

Managed config shared on macOS and Linux.

Initial suggested content:

```toml
onboarding = false

[ui]
show_agent_labels_on_pane_borders = true
agent_panel_scope = "all"
confirm_close = true

[ui.toast]
delivery = "terminal"
delay_seconds = 1

[ui.sound]
enabled = false

[worktrees]
# We do not rely on this as the source of truth because existing dotfiles use
# ~/Developer/<repo>.git/<worktree>. Keep it set to an explicit value in case
# Herdr-native worktree commands are used manually.
directory = "~/Developer/.herdr-worktrees"

# Keep prefix pane movement as the guaranteed fallback.
[keys]
focus_pane_left = "prefix+h"
focus_pane_down = "prefix+j"
focus_pane_up = "prefix+k"
focus_pane_right = "prefix+l"

# vim-herdr-navigation: seamless movement across Neovim splits and Herdr panes.
[[keys.command]]
key = "ctrl+h"
type = "plugin_action"
command = "vim-herdr-navigation.left"
description = "navigate left (vim/herdr)"

[[keys.command]]
key = "ctrl+j"
type = "plugin_action"
command = "vim-herdr-navigation.down"
description = "navigate down (vim/herdr)"

[[keys.command]]
key = "ctrl+k"
type = "plugin_action"
command = "vim-herdr-navigation.up"
description = "navigate up (vim/herdr)"

[[keys.command]]
key = "ctrl+l"
type = "plugin_action"
command = "vim-herdr-navigation.right"
description = "navigate right (vim/herdr)"
```

Notes:

- These global `ctrl+h/j/k/l` Herdr bindings intentionally shadow shell readline defaults like `ctrl+l` clear-screen and `ctrl+k` kill-line in non-Vim panes.
- Keep `prefix+h/j/k/l` as fallback for apps that should receive raw `ctrl+h/j/k/l` or for troubleshooting.
- Set `HERDR_NAV_PASSTHROUGH_RE` if a non-Vim TUI should receive the chords itself, for example `^(lazygit|k9s)$`.

### `nvim/lua/plugins/vim-herdr-navigation.lua`

Add the Neovim side of `paulbkim-dev/vim-herdr-navigation` through lazy.nvim.

Recommended spec:

```lua
return {
  "paulbkim-dev/vim-herdr-navigation",
  lazy = false,
  config = function(plugin)
    dofile(plugin.dir .. "/editor/nvim.lua")
  end,
}
```

This loads upstream `editor/nvim.lua`, which maps normal-mode `<C-h/j/k/l>` to:

1. move within Neovim windows first
2. if already at the edge and `$HERDR_PANE_ID` is set, run `herdr pane focus --direction ...`
3. otherwise fall back to tmux/plain Neovim behavior according to the plugin logic

Also remove or guard the existing direct mappings in `nvim/lua/config/remap.lua`:

```lua
-- remove once vim-herdr-navigation owns these
-- vim.keymap.set("n", "<c-k>", ":wincmd k<CR>")
-- vim.keymap.set("n", "<c-j>", ":wincmd j<CR>")
-- vim.keymap.set("n", "<c-h>", ":wincmd h<CR>")
-- vim.keymap.set("n", "<c-l>", ":wincmd l<CR>")
```

Because `nvim/lua/config/lazy.lua` loads `config.remap` after plugin setup, leaving those mappings active would override the plugin's edge-crossing behavior.

### `zsh/functions/rherdr`

Local macOS wrapper.

Usage:

```bash
rherdr <repo> [worktree-or-branch-or-pr]
```

Behavior:

1. Resolve host/user/home like existing `rdev`/`rpi`:
   - `RDEV_HOST:-rdev`
   - `RDEV_REMOTE_USER:-psteinroe`
   - `RDEV_HOME:-/home/$RDEV_REMOTE_USER`
   - `RDEV_DOTFILES:-$remote_home/Developer/dotfiles`
2. If no worktree arg is provided:
   - verify remote repo dir exists: `$remote_home/Developer/<repo>.git`
   - remotely run `hsyncworktrees --repo <repo> --prune`
3. If worktree arg is provided:
   - remotely run `wtensure` inside the bare repo with `WTENSURE_PRINT_PATH=1`
   - capture resolved worktree path
   - remotely run `hsyncworktrees --repo <repo> --focus-path <resolved-path> --prune`
4. Attach locally:

   ```bash
   herdr --remote "$host" --session "$repo"
   ```

5. Set Ghostty title similarly to other remote wrappers.

Important: `rherdr` should not create or kill tmux sessions.

Mosh option:

- accept `--mosh` to attach through Mosh after sync instead of Herdr remote thin client:

  ```bash
  rherdr --mosh <repo> [worktree-or-branch-or-pr]
  ```

- implementation can delegate to `rmherdr` after the same remote sync step.

### `zsh/functions/rmherdr`

Local macOS wrapper for roaming/mobile attach.

Usage:

```bash
rmherdr <repo> [worktree-or-branch-or-pr]
rherdr --mosh <repo> [worktree-or-branch-or-pr]
```

Behavior:

1. Reuse the same remote sync logic as `rherdr`:
   - verify repo exists
   - optionally run `wtensure`
   - run `hsyncworktrees --prune`
2. Attach with Mosh by running Herdr on the remote host:

   ```bash
   mosh "$host" -- sudo -u "$remote_user"      HOME="$remote_home" USER="$remote_user" LOGNAME="$remote_user"      PATH="$remote_path"      "$remote_home/.nix-profile/bin/herdr" --session "$repo"
   ```

3. If the remote `mosh-server` is not on the SSH login user's default PATH, pass an explicit server path:

   ```bash
   mosh --server="$remote_home/.nix-profile/bin/mosh-server" "$host" -- <remote-command>
   ```

4. If public UDP is unavailable, use a Tailscale SSH host alias, e.g. `rdev-ts`, and attach with:

   ```bash
   RDEV_MOSH_HOST=rdev-ts rmherdr hellomateo
   ```

5. If a narrow UDP range is configured, pass a port or range:

   ```bash
   mosh -p 60000:60020 "$host" -- <remote-command>
   ```

Tradeoffs versus `rherdr`:

- better roaming and sleep/wake behavior
- better behavior on lossy or high-latency links
- remote Herdr client/keybindings/config are used
- no Herdr local thin-client clipboard image-paste bridge
- requires UDP reachability and UTF-8 locale

### `zsh/functions/rmosh`

Optional generic helper for a resilient remote shell.

Usage:

```bash
rmosh [command...]
```

Behavior:

- defaults to an interactive remote zsh as `psteinroe`
- uses the same host/user/home/path variables as `rdev`
- useful for phone/tablet or unreliable networks when not specifically attaching to Herdr

Example remote command:

```bash
mosh "$host" -- sudo -u "$remote_user" HOME="$remote_home"   USER="$remote_user" LOGNAME="$remote_user" PATH="$remote_path"   "$remote_home/.nix-profile/bin/zsh" -l
```

### `zsh/functions/hsyncworktrees`

Remote/local helper. Must run on the machine where the repo and Herdr session live.

Usage:

```bash
hsyncworktrees [--repo <repo>] [--focus <worktree>] [--focus-path <path>] [--prune]
```

Allowed starting directories:

- bare repo root: `~/Developer/<repo>.git`
- any worktree for that repo

Behavior:

1. Ensure `herdr` is available; if missing, print a friendly message and return non-zero.
2. Resolve repo root from `git worktree list --porcelain` first `worktree` entry.
3. Derive project/session name:
   - if repo root basename is `<repo>.git`, session is `<repo>`
   - otherwise strip `.git` if present
4. Parse `git worktree list --porcelain` into rows:

   ```text
   branch-or-detached-or-bare<TAB>path<TAB>kind
   ```

5. For every non-bare worktree path:
   - compute label:
     - branch name if available
     - otherwise basename of path
     - PR numbers are already normalized by `wtensure` to `pr-<number>`
   - run with `HERDR_SESSION=<repo>`:

     ```bash
     herdr worktree open --path "$path" --label "$label" --no-focus --json
     ```

   - fallback if `worktree open` cannot handle an existing checkout:

     ```bash
     herdr workspace create --cwd "$path" --label "$label" --no-focus
     ```

6. Focus target if specified:
   - prefer path match via `herdr worktree list --json`
   - otherwise focus by workspace with matching cwd from `herdr workspace list`
7. If `--prune` is set:
   - list Herdr worktree/workspace entries associated with this repo/session
   - close workspaces whose cwd/path no longer exists on disk
   - do **not** delete Git worktrees or branches

Safety rules:

- `hsyncworktrees` never removes Git worktrees.
- `hsyncworktrees --prune` only closes Herdr workspaces whose cwd path is missing.
- If JSON parsing with `jq` fails, skip pruning rather than closing the wrong thing.

### `zsh/functions/hwtcreate`

Run inside a remote Herdr pane or any shell on the repo host.

Usage:

```bash
hwtcreate <branch-or-pr> [base]
```

Initial behavior:

1. Require a Git repo/worktree.
2. Use existing `wtensure` for branch/PR creation:

   ```bash
   source "$dotfiles/zsh/functions/wtensure" "$branch"
   ```

3. Run:

   ```bash
   hsyncworktrees --focus-path "$WTENSURE_WORKTREE_PATH" --prune
   ```

4. Optional later: if a base arg is provided, delegate to `wtcreate`/`rdevstack`-style branch creation from explicit base.

### `zsh/functions/_wt_herdr_helpers`

Shared functions used by `wtclean`, `wtforceclean`, and maybe `hsyncworktrees`.

Functions:

```zsh
_wt_herdr_available
_wt_herdr_repo_name [repo_root]
_wt_herdr_session_env [repo_name]
_wt_herdr_close_worktree_workspace <repo_root> <worktree_path>
_wt_herdr_prune_missing_workspaces <repo_root>
_wt_herdr_sync_worktrees <repo_root> [focus_path]
```

Guidelines:

- All helpers must be best-effort.
- If `herdr` is missing or no Herdr server/session is running, cleanup must still proceed.
- Use `HERDR_SESSION=<repo>` so commands target the project session.
- Prefer `herdr worktree list --json` for Herdr-native worktree entries.
- Fall back to `herdr workspace list` and cwd matching if needed.
- Never close workspaces whose cwd does not live under the current repo root unless the Herdr worktree metadata proves association.

### Optional local plugin: `herdr/plugins/worktree-sync/`

Structure:

```text
herdr/plugins/worktree-sync/
├── herdr-plugin.toml
├── sync.sh
├── create.sh
└── bootstrap.sh
```

Manifest sketch:

```toml
id = "psteinroe.worktree-sync"
name = "Worktree Sync"
version = "0.1.0"
min_herdr_version = "0.7.0"
description = "Sync Herdr project workspaces with psteinroe dotfiles worktrees."
platforms = ["linux", "macos"]

[[actions]]
id = "sync"
title = "Sync Git worktrees into Herdr workspaces"
contexts = ["workspace"]
command = ["zsh", "sync.sh"]

[[actions]]
id = "create"
title = "Create worktree and open workspace"
contexts = ["workspace"]
command = ["zsh", "create.sh"]

[[actions]]
id = "bootstrap"
title = "Bootstrap panes for this workspace"
contexts = ["workspace"]
command = ["zsh", "bootstrap.sh"]

# Optional only if Herdr-native worktree creation is used.
[[events]]
on = "worktree.created"
command = ["zsh", "sync.sh"]
```

Plugin action behavior:

- `sync.sh` calls the managed zsh helper:

  ```bash
  source "$HOME/Developer/dotfiles/zsh/functions/hsyncworktrees" --prune
  ```

- `create.sh` should probably open an overlay/prompt later. In v1, keep creation as shell command `hwtcreate <branch>` rather than an action requiring interactive input.
- `bootstrap.sh` can use Herdr CLI like the official `dev-layout-bootstrap` example:
  - rename current pane
  - split panes
  - start `pi`, `claude`, `just test`, server/log commands, etc.

When to add the plugin:

- after `rherdr`, `hsyncworktrees`, and cleanup hooks work reliably from plain shell commands.

## Files to modify

### `flake.nix`

Add Herdr and vim-herdr-navigation inputs.

Sketch:

```nix
herdr = {
  url = "github:ogulcancelik/herdr";
  inputs.nixpkgs.follows = "nixpkgs";
};

vim-herdr-navigation = {
  url = "github:paulbkim-dev/vim-herdr-navigation";
  flake = false;
};
```

Then pass `inputs` already available to Home Manager modules; no structural change needed beyond the input if `nix/home/packages.nix` consumes it.

Prefer pinning a release tag once a known-good version is selected:

```nix
url = "github:ogulcancelik/herdr/v0.x.y";
```

### `nix/home/packages.nix`

Add Herdr package similarly to existing optional flake packages.

Sketch:

```nix
herdr = lib.attrByPath [ system "default" ] null inputs.herdr.packages;
```

Then include:

```nix
++ optionalPackage herdr
```

Also add Mosh from nixpkgs to the common package list so both local macOS and remote Linux have `mosh`, `mosh-client`, and `mosh-server` available:

```nix
# Remote connectivity
mosh
```

Fallback if package attr differs after inspection:

- run `nix flake show github:ogulcancelik/herdr`
- use the actual package path exposed by the flake

### `nix/home/common.nix`

Symlink Herdr config:

```nix
xdg.configFile = {
  # existing entries...
  "herdr/config.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/herdr/config.toml";
};
```

### `nix/home/shell.nix`

Autoload new helpers:

```zsh
autoload -Uz rherdr
autoload -Uz rmherdr
autoload -Uz rmosh
autoload -Uz hsyncworktrees
autoload -Uz hwtcreate
```

`_wt_herdr_helpers` is sourced by other functions and does not need direct autoload unless used interactively.

### `ssh_config` and optional Tailscale host alias

Mosh uses SSH only for setup, then UDP to the selected host. If `psteinroe-dev.exe.xyz` does not expose UDP, add a Tailscale-specific host alias and use it for Mosh attach.

Example:

```sshconfig
Host rdev-ts
  HostName psteinroe-dev
  User exedev
  IdentityFile ~/.ssh/id_ed25519
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h:%p
  ControlPersist 10m
```

Exact `HostName` should be whichever Tailscale MagicDNS name or 100.x address is stable for the devbox.

Keep `rdev` as the normal SSH/Herdr thin-client alias. Use `rdev-ts` through `RDEV_MOSH_HOST` only if Mosh over the public/exe.dev endpoint cannot receive UDP.

### Remote firewall / UDP access for Mosh

Mosh needs UDP from client to remote host. Options:

1. **Preferred:** use Tailscale path for Mosh, avoiding public firewall/NAT surprises.
2. **If public UDP is available:** allow a small UDP range such as `60000-60020` rather than the full default `60000-61000`.
3. **If using a fixed port/range:** configure wrappers to pass `-p`, e.g. `MOSH_PORTS=60000:60020`.

Validation command:

```bash
mosh -p 60000:60020 rdev-ts -- true
```

If Mosh reports `Nothing received from the server on UDP port ...`, SSH setup worked but UDP is blocked or routed incorrectly.

### `nix/home/agents.nix` or a new `nix/home/herdr.nix`

Link `vim-herdr-navigation` as a Herdr plugin after Herdr is installed.

Activation sketch:

```nix
home.activation.herdrPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  if command -v herdr >/dev/null 2>&1; then
    herdr plugin link ${inputs.vim-herdr-navigation} >/dev/null 2>&1 || true
  fi
'';
```

Notes:

- `herdr plugin link` can point at the pinned Nix store checkout because the plugin runs `bash navigate.sh`; it does not need to write into the plugin root.
- If Herdr refuses to replace an existing link, explicitly `herdr plugin unlink vim-herdr-navigation` before linking.
- Verify with:

  ```bash
  herdr plugin action list --plugin vim-herdr-navigation
  ```

- This plugin requires `jq`, which is already in the common package list.

### `nix/home/agents.nix`

Install Herdr integrations idempotently after managed agent configs are deployed.

Important constraint: Herdr integration installers modify agent config directories. This repo also manages those configs. Therefore activation must run **after** existing `agentConfigs` content is in place.

Simplest plan:

1. Keep existing config deployment as source of truth.
2. Add a second activation step after `agentConfigs`:

   ```nix
   home.activation.herdrAgentIntegrations = lib.hm.dag.entryAfter [ "agentConfigs" ] ''
     if command -v herdr >/dev/null 2>&1; then
       herdr integration install pi >/dev/null 2>&1 || true
       herdr integration install claude >/dev/null 2>&1 || true
       herdr integration install codex >/dev/null 2>&1 || true
       herdr integration install opencode >/dev/null 2>&1 || true
     fi
   '';
   ```

3. Verify that the generated integration hooks/plugins survive and do not fight the dotfiles symlinks.

If installers conflict with symlinked config files:

- copy generated Herdr hook/plugin files into `agents/*` explicitly
- update managed `settings.json` / `config.toml` with Herdr hook entries by hand
- stop running `herdr integration install` on every activation

### `nix/home/remote-skills.nix`

Add Herdr agent skill as a pinned skill source.

Options:

1. Add Herdr as flake input and reference `${inputs.herdr}/SKILL.md` by wrapping it in a local skill directory.
2. Simpler: create local `agents/skills/herdr/SKILL.md` by copying the upstream Herdr `SKILL.md` and update manually when Herdr changes.

Recommended for stability:

```text
agents/skills/herdr/SKILL.md
```

Then existing `deploy_local_skill_dir` in `nix/home/agents.nix` will deploy it to Pi/Claude/Codex/OpenCode.

### `zsh/functions/wtclean`

Add Herdr-aware cleanup around the existing tmux cleanup.

Before `git worktree remove --force "$worktree_path"`, call:

```zsh
if (( $+functions[_wt_herdr_close_worktree_workspace] )); then
  _wt_herdr_close_worktree_workspace "$session_repo_root" "$worktree_path"
fi
```

After `git worktree prune`, call:

```zsh
if (( $+functions[_wt_herdr_prune_missing_workspaces] )); then
  _wt_herdr_prune_missing_workspaces "$session_repo_root"
fi
```

Keep tmux cleanup in place until tmux is fully retired.

### `zsh/functions/wtforceclean`

Same as `wtclean`:

1. close matching Herdr workspace
2. kill matching tmux session
3. remove Git worktree
4. prune missing Herdr workspaces

### `zsh/functions/rwtclean`

Can remain mostly unchanged because it remotely sources `wtclean`.

Optional improvement after remote `wtclean` completes:

```zsh
# remote: cd repo_dir && source hsyncworktrees --prune
```

This is redundant if `wtclean` already prunes Herdr state.

### `zsh/functions/rwtforceclean`

Can remain mostly unchanged because it remotely sources `wtforceclean`.

Optional redundant final prune is acceptable.

### `ghostty.conf`

Current Ghostty config uses performable split focus bindings:

```text
keybind = performable:ctrl+h=goto_split:left
keybind = performable:ctrl+j=goto_split:bottom
keybind = performable:ctrl+k=goto_split:top
keybind = performable:ctrl+l=goto_split:right
```

Decision for first implementation: keep these initially.

Rationale:

- `performable:` should pass the chord through when the focused terminal app can handle it.
- Inside Herdr, Herdr should receive the chord and dispatch `vim-herdr-navigation`.
- Outside Herdr, Ghostty split navigation remains useful.

If testing shows Ghostty consumes the chord before Herdr, remove or change these bindings and rely on Herdr/Neovim for `ctrl+h/j/k/l` inside Herdr sessions.

### `README.md`

Update the Remote Dev Workflow section with:

```bash
rherdr hellomateo                # attach via Herdr local thin client
rherdr hellomateo feature-x      # ensure/focus worktree workspace, then attach
rmherdr hellomateo               # attach via Mosh for roaming/flaky networks
rherdr --mosh hellomateo         # equivalent Mosh mode if implemented as flag
hwtcreate feature-y              # from inside Herdr: create worktree workspace
hsyncworktrees --prune           # sync Herdr workspace list with Git worktrees
```

Mention:

- `rdev` remains tmux fallback.
- `rpi` remains special local-Pi/remote-tools mode.
- `rherdr` is the default project UI once stable.

## Detailed command behavior

### `rherdr hellomateo`

Expected behavior:

1. Remote repo exists:

   ```text
   /home/psteinroe/Developer/hellomateo.git
   ```

2. Remote sync runs in session `hellomateo`.
3. Herdr opens one workspace per existing non-bare worktree.
4. Local thin client attaches:

   ```bash
   herdr --remote rdev --session hellomateo
   ```

### `rherdr hellomateo feature-x`

Expected behavior:

1. Remote `wtensure feature-x` creates or updates:

   ```text
   /home/psteinroe/Developer/hellomateo.git/feature-x
   ```

2. Sync opens/focuses workspace `feature-x`.
3. Local thin client attaches to session `hellomateo`.

### `rmherdr hellomateo feature-x`

Expected behavior:

1. Runs the same remote preparation as `rherdr hellomateo feature-x`.
2. Starts a Mosh connection to the remote host.
3. Runs `herdr --session hellomateo` on the remote host as user `psteinroe`.
4. Uses the remote Herdr client and remote Herdr config.
5. Survives laptop sleep/wake and network roaming better than SSH.

Use this mode when mobility/connection resilience matters more than Herdr `--remote` thin-client features.

### `hwtcreate feature-y`

Expected behavior inside remote Herdr pane:

1. Creates worktree via existing conventions.
2. Opens/focuses workspace `feature-y` in the current project session.
3. Leaves current shell usable.

### `ctrl+h/j/k/l` inside Herdr + Neovim

Expected behavior with `vim-herdr-navigation`:

- In a normal shell pane: `ctrl+h/j/k/l` moves Herdr focus to the adjacent pane.
- In a Neovim pane with multiple splits: the same keys move between Neovim splits first.
- At the edge of Neovim splits: the same key crosses into the adjacent Herdr pane.
- Prefix movement still works everywhere:

  ```text
  prefix+h/j/k/l
  ```

Known tradeoffs:

- `ctrl+l` no longer clears the shell in Herdr panes unless the pane/app is passthrough.
- `ctrl+k` no longer kills the readline line in Herdr panes unless passthrough.
- Configure `HERDR_NAV_PASSTHROUGH_RE` for TUIs like `lazygit` or `k9s` if needed.

### `rwtclean hellomateo`

Expected behavior:

1. Remote `wtclean` lists worktrees and checks PR states.
2. User confirms merged/closed removals.
3. For each selected worktree:
   - close Herdr workspace for that path if present
   - kill tmux session for that path if present
   - remove Git worktree
4. Prune Git worktree metadata.
5. Prune missing Herdr workspaces.

### `rwtforceclean hellomateo`

Expected behavior:

1. Remote `wtforceclean` fzf-selects worktrees.
2. User types `force`.
3. For each selected worktree:
   - close Herdr workspace
   - kill tmux session
   - force-remove Git worktree
4. Prune Git and Herdr state.

## Cleanup and safety model

Destructive actions are split deliberately:

| Command | Can create Git worktrees | Can delete Git worktrees | Can close Herdr workspaces | Can kill tmux |
| --- | --- | --- | --- | --- |
| `rherdr` | only when worktree arg provided through `wtensure` | no | only stale missing workspaces with `--prune` | no |
| `hsyncworktrees` | no | no | only stale missing workspaces with `--prune` | no |
| `hwtcreate` | yes | no | no, except focus/open sync | no |
| `wtclean` | no | yes, after confirmation | yes, matching removed paths | yes |
| `wtforceclean` | no | yes, after `force` | yes, matching removed paths | yes |
| `rwtclean` | no | yes, through remote `wtclean` | yes, through remote `wtclean` | yes |
| `rwtforceclean` | no | yes, through remote `wtforceclean` | yes, through remote `wtforceclean` | yes |

Rules:

- Never delete Git worktrees from Herdr sync alone.
- Never close Herdr workspaces by label alone; use path/cwd/worktree metadata.
- Protected branches remain protected in cleanup: default branch, `main`, `master`, `trunk`.
- If Herdr is missing/unavailable, cleanup still removes Git worktrees and tmux sessions as before.
- If JSON parsing fails, skip Herdr pruning rather than risk closing the wrong workspace.

## Testing plan

### 1. Nix build checks

Local macOS:

```bash
nix flake check
nix build .#darwinConfigurations.psteinroe.system
```

Remote Linux Home Manager:

```bash
ssh rdev 'sudo -u psteinroe HOME=/home/psteinroe /home/psteinroe/.nix-profile/bin/zsh -lc "cd ~/Developer/dotfiles && home-manager build --flake .#psteinroe@linux-x86_64"'
```

### 2. Herdr install checks

Local:

```bash
command -v herdr
herdr --version
```

Remote:

```bash
ssh rdev 'sudo -u psteinroe HOME=/home/psteinroe PATH=/home/psteinroe/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin herdr --version'
```

### 3. Remote attach smoke test

```bash
herdr --remote rdev --session dotfiles
```

Detach with Herdr prefix + `q`.

### 3b. Mosh attach smoke test

Verify both ends have Mosh:

```bash
command -v mosh
ssh rdev 'command -v mosh-server || command -v /home/psteinroe/.nix-profile/bin/mosh-server'
```

Try the Tailscale alias first if available:

```bash
mosh rdev-ts -- true
```

Then try remote Herdr over Mosh:

```bash
rmherdr dotfiles
# or
rherdr --mosh dotfiles
```

If it fails after SSH setup with `Nothing received from the server on UDP port ...`, fix UDP routing/firewall or use the Tailscale host alias.

### 4. Worktree sync dry run

On remote:

```bash
cd ~/Developer/hellomateo.git
hsyncworktrees --prune
HERDR_SESSION=hellomateo herdr workspace list
HERDR_SESSION=hellomateo herdr worktree list --json
```

### 5. `rherdr` smoke test

```bash
rherdr hellomateo
rherdr hellomateo test-herdr-plan
```

Verify:

- session name is `hellomateo`
- workspace label/path matches created worktree
- detach/reattach preserves shell panes

### 6. Cleanup test with disposable branch

```bash
rherdr hellomateo herdr-cleanup-test
# inside or outside Herdr, make no important changes
rwtforceclean hellomateo
```

Verify:

- worktree directory is gone
- Herdr workspace is closed/pruned
- no protected worktree was offered for deletion

### 7. Agent integration checks

Inside a Herdr pane:

```bash
pi --version
claude --version
codex --version
opencode --version
herdr agent list
herdr integration status
```

Verify Herdr reports useful state for each supported agent after starting them in panes.

### 8. Neovim navigation plugin checks

Inside a Herdr workspace:

```bash
herdr plugin action list --plugin vim-herdr-navigation
nvim
```

In Neovim:

```vim
:vsplit
:split
```

Verify:

- `ctrl+h/j/k/l` moves between Neovim splits.
- At split edges, `ctrl+h/j/k/l` crosses into adjacent Herdr panes.
- In a shell pane, `ctrl+h/j/k/l` moves Herdr pane focus.
- `prefix+h/j/k/l` still works as fallback.

If it does not work:

- confirm `$HERDR_PANE_ID` is set inside Neovim
- confirm `jq` is installed
- confirm `herdr pane process-info --current` identifies the foreground process
- confirm Ghostty is not consuming the key before Herdr

## Rollout plan

### Phase A: Install and manual validation

- Add Herdr flake input/package.
- Add config symlink.
- Rebuild local and remote.
- Manually run `herdr --remote rdev --session dotfiles`.

### Phase A2: Mosh install and connectivity validation

- Add `mosh` to Home Manager packages.
- Rebuild local and remote.
- Verify `mosh` locally and `mosh-server` remotely.
- Add optional `rdev-ts` SSH alias if public UDP is unavailable.
- Validate `mosh rdev-ts -- true` or `mosh rdev -- true`.
- Do not make Mosh the default attach path yet.

### Phase A3: Neovim/Herdr navigation

- Add `vim-herdr-navigation` flake input.
- Link the Herdr plugin during Home Manager activation.
- Add `nvim/lua/plugins/vim-herdr-navigation.lua` lazy spec.
- Remove/guard existing `nvim/lua/config/remap.lua` `<C-h/j/k/l>` direct `wincmd` mappings.
- Add Herdr `ctrl+h/j/k/l` plugin-action keybindings.
- Test in Herdr shell panes and Neovim split edges.

### Phase B: Shell sync MVP

- Add `hsyncworktrees`.
- Add `rherdr`.
- Test with `dotfiles` or another low-risk repo.
- Do not modify cleanup yet.

### Phase C: Create-from-Herdr

- Add `hwtcreate`.
- Test creating disposable worktrees from inside a Herdr pane.

### Phase D: Cleanup integration

- Add `_wt_herdr_helpers`.
- Modify `wtclean` and `wtforceclean`.
- Verify `rwtclean` and `rwtforceclean` inherit behavior.

### Phase E: Agent integration and skill

- Add Herdr agent integrations through activation or managed config changes.
- Add Herdr skill to `agents/skills/herdr/SKILL.md`.
- Validate Pi/Claude/Codex/OpenCode status and session restore.

### Phase F: Optional plugin

- Add local plugin directory.
- Link it declaratively or with an idempotent activation command:

  ```bash
  herdr plugin link "$HOME/Developer/dotfiles/herdr/plugins/worktree-sync" >/dev/null 2>&1 || true
  ```

- Add keybindings in `herdr/config.toml` if useful:

  ```toml
  [[keys.command]]
  key = "prefix+shift+s"
  type = "plugin_action"
  command = "psteinroe.worktree-sync.sync"
  description = "sync worktrees"
  ```

## Open questions before implementation

1. Should `rherdr <repo>` auto-start a default shell/agent pane for every worktree, or only create workspaces and let the user start panes manually?
2. Should `hwtcreate` support explicit base branches immediately, or should stacked branch creation stay in `rdevstack` for now?
3. Should Herdr integrations be installed by running `herdr integration install` during Home Manager activation, or should their generated hook files be copied into the dotfiles and managed directly?
4. Should Herdr plugin linking happen automatically on rebuild, or should the plugin remain a later manual opt-in?
5. Should the default remote workflow switch from `rdev` to `rherdr` in README immediately, or only after a trial period?
6. Should Mosh use the public `rdev` hostname or a separate Tailscale-only alias such as `rdev-ts`?
7. Should Mosh use the default UDP range `60000-61000`, or should wrappers enforce a narrower range such as `60000-60020`?
8. Should `HERDR_NAV_PASSTHROUGH_RE` include `lazygit`, `k9s`, or other TUIs by default?

## Recommended answer to open questions for first implementation

1. Only create/focus workspaces initially. Add pane bootstrapping later.
2. Keep explicit stacked-branch creation in `rdevstack` initially.
3. Try `herdr integration install` in activation; if it fights symlinks, switch to managed generated files.
4. Do not link a plugin in the first implementation; keep plugin as Phase F.
5. Document `rherdr` as experimental/default-candidate, with `rdev` as stable fallback.
6. Prefer a Tailscale-only alias for Mosh unless the public/exe.dev endpoint is known to pass UDP reliably.
7. Use a narrow UDP range initially, e.g. `60000-60020`, and make it configurable with `MOSH_PORTS`.
8. Start with `HERDR_NAV_PASSTHROUGH_RE='^(lazygit|k9s)$'` if those tools are commonly used inside Herdr panes; otherwise leave it unset until a conflict appears.
