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
- **Roaming/mobile/bad-network mode:** deferred to `TAILSCALE_PLAN.md` once Tailscale UDP connectivity is working.
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
- Mosh over the public exe.dev hostname appears out of scope for this Herdr rollout because it needs UDP and belongs with the Tailscale transport migration. See `TAILSCALE_PLAN.md` for the Mosh follow-up.

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

### Plugin-system evidence from `cloudmanic/herdr-plus`

`cloudmanic/herdr-plus` demonstrates the plugin system is already powerful enough for most of what we want:

- It installs as a normal Herdr plugin with `herdr plugin install cloudmanic/herdr-plus`.
- Its manifest declares actions and panes for fuzzy project/quick-action launchers.
- Its manifest declares `[[events]]` for `worktree.created` and `worktree.opened`.
- Its worktree handler reads `HERDR_PLUGIN_EVENT_JSON` plus `HERDR_WORKSPACE_ID`, `HERDR_TAB_ID`, and `HERDR_PANE_ID`.
- It applies layouts by calling Herdr socket/CLI APIs such as pane split/send-input, tab create, workspace create/close, pane list/get/read.
- Its config is stored in Herdr's managed plugin config dir via `HERDR_PLUGIN_CONFIG_DIR`.

Implication for us:

- Build a dotfiles-owned plugin that wraps our existing worktree conventions and exposes Herdr-native actions.
- Use shell wrappers only for pre-attach concerns such as `rherdr <repo> [branch]` and SSH connection selection.
- Let the plugin own in-session operations: sync, open existing worktree, create worktree, cleanup UI, and layout bootstrap.

## Files to add

### `herdr/config.toml`

Managed config shared on macOS and Linux.

Initial suggested content:

```toml
onboarding = false

[theme]
# Match the rest of the dotfiles: Ghostty uses "Gruvbox Dark Hard",
# Neovim uses gruvbox-material hard, tuicr/Pi use Gruvbox variants.
# Herdr exposes built-in "gruvbox" / "gruvbox-light".
name = "gruvbox"
auto_switch = false
# If we ever want host light/dark switching:
# auto_switch = true
# dark_name = "gruvbox"
# light_name = "gruvbox-light"

[ui]
show_agent_labels_on_pane_borders = true
agent_panel_scope = "all"
confirm_close = true

[remote]
# Herdr --remote writes a private temporary SSH config that includes
# ~/.ssh/config and /etc/ssh/ssh_config, then adds fallback keepalives.
# Our rdev SSH alias remains the source of truth and user settings win.
manage_ssh_config = true

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

# Tmux-ish, smooth keymap.
[keys]
prefix = "ctrl+b"

# Basics.
help = "prefix+?"
detach = ["prefix+d", "prefix+q"]
reload_config = "prefix+shift+r"
goto = "prefix+g"

# Workspaces are project/worktree views. Keep both Herdr and tmux-ish muscle memory.
workspace_picker = ["prefix+w", "prefix+s"]
new_workspace = "prefix+shift+n"
rename_workspace = "prefix+shift+w"
close_workspace = "prefix+shift+d"
previous_workspace = "prefix+("
next_workspace = "prefix+)"

# Tabs are closest to tmux windows.
new_tab = "prefix+c"
previous_tab = "prefix+p"
next_tab = "prefix+n"
switch_tab = "prefix+1..9"
rename_tab = "prefix+comma"
close_tab = "prefix+shift+x"

# Pane creation/management.
split_vertical = "prefix+backslash" # split right, like tmux split-window -h
split_horizontal = "prefix+minus"   # split down
close_pane = "prefix+x"
zoom = "prefix+z"
copy_mode = "prefix+["
resize_mode = "prefix+r"
cycle_pane_next = "prefix+tab"
cycle_pane_previous = "prefix+shift+tab"

# Prefix pane movement remains the guaranteed fallback.
focus_pane_left = "prefix+h"
focus_pane_down = "prefix+j"
focus_pane_up = "prefix+k"
focus_pane_right = "prefix+l"

# Herdr navigate-mode movement.
navigate_workspace_up = "up"
navigate_workspace_down = "down"
navigate_pane_left = "h"
navigate_pane_down = "j"
navigate_pane_up = "k"
navigate_pane_right = "l"

# Disable native Herdr worktree shortcuts; our plugin owns these flows.
new_worktree = ""
open_worktree = ""
remove_worktree = ""

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

# Dotfiles worktree plugin shortcuts.
[[keys.command]]
key = "prefix+shift+g"
type = "plugin_action"
command = "psteinroe.worktree-sync.create"
description = "create worktree"

[[keys.command]]
key = "prefix+shift+o"
type = "plugin_action"
command = "psteinroe.worktree-sync.open"
description = "open worktree"

[[keys.command]]
key = "prefix+shift+h"
type = "plugin_action"
command = "psteinroe.worktree-sync.hide"
description = "hide current worktree"

[[keys.command]]
key = "prefix+shift+m"
type = "plugin_action"
command = "psteinroe.worktree-sync.manager"
description = "worktree manager"

[[keys.command]]
key = "prefix+shift+s"
type = "plugin_action"
command = "psteinroe.worktree-sync.sync-visible"
description = "sync visible worktrees"

[[keys.command]]
key = "prefix+alt+s"
type = "plugin_action"
command = "psteinroe.worktree-sync.sync-all"
description = "open all worktrees"

[[keys.command]]
key = "prefix+alt+d"
type = "plugin_action"
command = "psteinroe.worktree-sync.clean"
description = "clean worktrees"
```

Notes:

- `ctrl+h/j/k/l` is the smooth movement layer across Neovim splits and Herdr panes, via `vim-herdr-navigation`.
- These global `ctrl+h/j/k/l` bindings intentionally shadow shell readline defaults like `ctrl+l` clear-screen and `ctrl+k` kill-line in non-Vim panes.
- Keep `prefix+h/j/k/l` as fallback for apps that should receive raw `ctrl+h/j/k/l` or for troubleshooting.
- Worktree shortcuts are plugin-owned: `prefix+shift+g` create, `prefix+shift+o` open, `prefix+shift+h` hide, `prefix+shift+m` manager, `prefix+alt+d` clean.
- Set `HERDR_NAV_PASSTHROUGH_RE` if a non-Vim TUI should receive the chords itself, for example `^(lazygit|k9s)$`.
- Theme choice is `gruvbox` because the repo consistently uses Gruvbox variants: Ghostty `Gruvbox Dark Hard`, Neovim `gruvbox-material` hard, tuicr `gruvbox-readable`, and Pi `gruvbox-high-contrast`.
- `[remote].manage_ssh_config = true` only affects Herdr thin-client mode (`herdr --remote ...`). Mosh is deferred to `TAILSCALE_PLAN.md`.

### Keybinding rationale

This keymap is deliberately close to tmux while keeping Herdr defaults where they are already good:

- Herdr/tmux default prefix stays `ctrl+b`.
- `prefix+c`, `prefix+n`, `prefix+p`, `prefix+1..9`, `prefix+x`, `prefix+z`, and `prefix+[` retain familiar tmux/Herdr meanings.
- `prefix+backslash` follows tmux's horizontal split muscle memory for "split right".
- `prefix+minus` stays Herdr's default split-down binding because it is easy and documented.
- `prefix+w` remains Herdr workspace navigation; `prefix+s` is added as a tmux-session-like workspace picker.
- Direct `ctrl+h/j/k/l` is handled by `vim-herdr-navigation`, mirroring the `vim-tmux-navigator` experience and examples from Herdr users.
- `prefix+h/j/k/l` remains fallback pane focus if direct navigation conflicts with a TUI.
- Native Herdr worktree shortcuts are disabled so `psteinroe.worktree-sync` owns create/open/hide/clean semantics for the existing `~/Developer/<repo>.git/<worktree>` layout.

Daily muscle memory target:

```text
ctrl+h/j/k/l       move through Neovim splits and Herdr panes
prefix+h/j/k/l     fallback pane movement
prefix+\          split right
prefix+-           split down
prefix+c           new tab
prefix+n/p         next/previous tab
prefix+w or s      workspace picker
prefix+shift+g     create worktree
prefix+shift+o     open worktree
prefix+shift+h     hide current worktree
prefix+shift+m     worktree manager
prefix+alt+d       clean worktrees
prefix+d or q      detach
```

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

Mosh/roaming attach is intentionally deferred to `TAILSCALE_PLAN.md`; `rherdr` should stay focused on Herdr remote attach for this rollout.

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

### Overriding Herdr worktree handling for this repo layout

Herdr has a built-in `[worktrees].directory`, but it creates checkouts under:

```text
<directory>/<repo>/<branch-slug>
```

Our established layout is different:

```text
~/Developer/<repo>.git/<worktree>
```

Therefore the plan is **not** to make Herdr's built-in creation path the source of truth. Instead:

- use Herdr workspaces/worktree records to represent existing worktrees
- use our wrappers/plugins to create/delete/sync worktrees according to the dotfiles layout
- keep Herdr-native worktree creation as a manual fallback only

Concretely:

1. `hsyncworktrees` opens existing dotfiles-layout worktrees in Herdr:

   ```bash
   HERDR_SESSION=<repo> herdr worktree open      --path ~/Developer/<repo>.git/<worktree>      --label <worktree>      --no-focus      --json
   ```

2. If `herdr worktree open` is too opinionated for an existing checkout, fallback to plain workspaces:

   ```bash
   HERDR_SESSION=<repo> herdr workspace create      --cwd ~/Developer/<repo>.git/<worktree>      --label <worktree>      --no-focus
   ```

3. `hwtcreate <branch>` creates via existing `wtensure`/`wtcreate` semantics, then calls `hsyncworktrees --focus-path ...`.

4. Cleanup remains owned by `wtclean`/`wtforceclean`; those commands close matching Herdr workspaces before removing Git worktrees.

5. Optional keybinding override: disable Herdr's built-in `new_worktree` binding and put our custom action on the same key:

   ```toml
   [keys]
   new_worktree = ""

   [[keys.command]]
   key = "prefix+shift+g"
   type = "plugin_action"
   command = "psteinroe.worktree-sync.create"
   description = "create dotfiles-layout worktree"

   [[keys.command]]
   key = "prefix+shift+o"
   type = "plugin_action"
   command = "psteinroe.worktree-sync.open"
   description = "open dotfiles-layout worktree"

   [[keys.command]]
   key = "prefix+shift+m"
   type = "plugin_action"
   command = "psteinroe.worktree-sync.manager"
   description = "worktree manager for this project"
   ```

6. The sidebar/context-menu built-in worktree action may still exist. Treat it as unsupported for repos managed by these dotfiles unless Herdr later exposes a path-template/hook setting.

Why not just set `[worktrees].directory = "~/Developer"`?

- Herdr would create `~/Developer/<repo>/<branch>`, not `~/Developer/<repo>.git/<branch>`.
- It would not reuse the existing bare-repo root as the parent directory.
- It would diverge from `wtensure`, `rwtclone`, `rwtclean`, `rdevstack`, and the tmux fallback flow.

If Herdr later adds a configurable worktree path template or creation hook, replace `hwtcreate`/plugin creation with that native extension point.

Herdr-plus-style event hooks give us one extra win: if a user does use a Herdr-native worktree dialog, our plugin can still catch `worktree.created` / `worktree.opened` and apply layout/bootstrap. It cannot change where Herdr created that checkout after the fact, but it can keep the experience consistent once a workspace exists.

### First-class local plugin: `herdr/plugins/worktree-sync/`

`cloudmanic/herdr-plus` proves the Herdr plugin system is powerful enough for this workflow. It uses actions, panes, and `worktree.created` / `worktree.opened` event hooks to apply layouts automatically when Herdr creates or opens worktrees. We should treat our project/worktree integration as a first-class plugin, not just a later nice-to-have.

Structure:

```text
herdr/plugins/worktree-sync/
├── herdr-plugin.toml
├── lib/project-context.zsh
├── sync.sh
├── open.sh
├── create.sh
├── clean.sh
├── bootstrap.sh
├── on-worktree.sh
└── manager.sh
```

Important product decision: **one Herdr named session is one project/repo**. Plugin UIs must not ask the user to select a repo. They should infer the project from the current Herdr session/workspace context and only ask for worktree-specific inputs such as branch name, base branch, PR number, or layout.

Manifest sketch:

```toml
id = "psteinroe.worktree-sync"
name = "Worktree Sync"
version = "0.1.0"
min_herdr_version = "0.7.0"
description = "Make Herdr workspaces follow psteinroe dotfiles worktrees."
platforms = ["linux", "macos"]

[[actions]]
id = "sync"
title = "Sync Git worktrees into Herdr workspaces"
contexts = ["workspace"]
command = ["zsh", "sync.sh"]

[[actions]]
id = "open"
title = "Open existing dotfiles worktree"
contexts = ["workspace"]
command = ["zsh", "open.sh"]

[[actions]]
id = "create"
title = "Create dotfiles-layout worktree"
contexts = ["workspace"]
command = ["zsh", "create.sh"]

[[actions]]
id = "clean"
title = "Clean merged/closed worktrees"
contexts = ["workspace"]
command = ["zsh", "clean.sh"]

[[actions]]
id = "bootstrap"
title = "Bootstrap panes for this workspace"
contexts = ["workspace"]
command = ["zsh", "bootstrap.sh"]

[[panes]]
id = "manager"
title = "Worktree Manager"
placement = "overlay"
command = ["zsh", "manager.sh"]

# Catch Herdr-native worktree operations too.
[[events]]
on = "worktree.created"
command = ["zsh", "on-worktree.sh"]

[[events]]
on = "worktree.opened"
command = ["zsh", "on-worktree.sh"]
```

Plugin action behavior:

- `lib/project-context.zsh` resolves the current project without repo selection:
  1. Prefer the active workspace/worktree cwd from `HERDR_PLUGIN_CONTEXT_JSON`.
  2. Walk up through `git worktree list --porcelain` to find the bare repo root.
  3. Derive project name from `<repo>.git` basename.
  4. Load optional repo config from `$HERDR_PLUGIN_CONFIG_DIR/repos/<project>.toml`.
  5. If no active cwd is available, fail with a clear message: "Open this action from a project/worktree workspace." Do not show a repo picker.
- `sync.sh` calls the managed zsh helper from the resolved repo/bare dir:

  ```bash
  cd "$PROJECT_BARE_DIR" && source "$HOME/Developer/dotfiles/zsh/functions/hsyncworktrees" --prune
  ```

- `open.sh` should fuzzy-pick only among worktrees for the current project, then call `herdr worktree open --path ...` or focus an existing matching workspace.
- `create.sh` should prompt for branch/base/PR for the current project only, run `wtensure`/`wtcreate`, then call `hsyncworktrees --focus-path ...`.
- `clean.sh` should launch the existing safe cleanup flow (`wtclean` or `wtforceclean`) for the current project only, so confirmation remains explicit.
- `manager.sh` is an overlay TUI for the current project only:
  - show project name and bare dir at the top
  - list current worktrees
  - actions: open, create, sync, clean, bootstrap
  - no repo selector
- `on-worktree.sh` should react to Herdr's `worktree.created` / `worktree.opened` events and apply a repo layout if one exists.
- `bootstrap.sh` can use Herdr CLI like the official `dev-layout-bootstrap` and `herdr-plus` examples:
  - rename current pane
  - split panes
  - create tabs
  - start `pi`, `claude`, `just test`, server/log commands, etc.

Plugin config directory:

```text
$HERDR_PLUGIN_CONFIG_DIR/
├── repos/
│   ├── hellomateo.toml
│   └── postgres-language-server.toml
├── layouts/
│   ├── default.toml
│   └── hellomateo.toml
└── quick-actions/
```

Repo config sketch:

```toml
# File: $HERDR_PLUGIN_CONFIG_DIR/repos/hellomateo.toml
# This config supplements inferred context; it is not selected interactively.
name = "hellomateo"
bare_dir = "~/Developer/hellomateo.git"
default_branch = "main"

[layout]
name = "default"

[[tabs]]
name = "agent"
command = "pi"

[[tabs]]
name = "shell"

[[tabs]]
name = "git"
command = "lazygit"
```

Create UI flow:

```text
prefix+shift+g
→ psteinroe.worktree-sync.create
→ overlay/pane for current project, e.g. "hellomateo"
→ prompt: branch or PR number
→ optional prompt/fzf: base branch, defaulting to repo config default_branch
→ run wtensure/wtcreate in ~/Developer/hellomateo.git
→ hsyncworktrees --focus-path <new-worktree>
→ focus new workspace
→ optionally offer bootstrap layout
```

Open UI flow:

```text
prefix+shift+o
→ psteinroe.worktree-sync.open
→ fzf only worktrees from the current repo
→ focus existing workspace or open missing workspace
```

Manager UI flow:

```text
prefix+shift+m
→ psteinroe.worktree-sync.manager pane
→ current project dashboard
→ no repo picker
```

When to add the plugin:

- move it earlier than originally planned: implement shell helpers first, then immediately wrap them with plugin actions once sync/create/cleanup semantics are clear.

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
autoload -Uz hsyncworktrees
autoload -Uz hwtcreate
```

`_wt_herdr_helpers` is sourced by other functions and does not need direct autoload unless used interactively.

### Tailscale/Mosh follow-up

Mosh and Tailscale host-alias work has moved to `TAILSCALE_PLAN.md`. The Herdr rollout should not add `rdev-ts`, `rmherdr`, `rmosh`, or Mosh package requirements until the Tailscale transport migration validates UDP connectivity.

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

Verify config intent:

```bash
herdr status client
herdr --default-config | rg -n "\[theme\]|\[remote\]|manage_ssh_config"
```

Expected plan values once `herdr/config.toml` exists:

- `[theme].name = "gruvbox"`
- `[remote].manage_ssh_config = true`

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

### Phase F: First-class worktree plugin

- Add local plugin directory for `psteinroe.worktree-sync`.
- Expose sync/open/create/clean/bootstrap actions and worktree event handlers.
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
6. Should `HERDR_NAV_PASSTHROUGH_RE` include `lazygit`, `k9s`, or other TUIs by default?

## Recommended answer to open questions for first implementation

1. Only create/focus workspaces initially. Add pane bootstrapping later.
2. Keep explicit stacked-branch creation in `rdevstack` initially.
3. Try `herdr integration install` in activation; if it fights symlinks, switch to managed generated files.
4. Do not link a plugin in the first implementation; keep plugin as Phase F.
5. Document `rherdr` as experimental/default-candidate, with `rdev` as stable fallback.
6. Start with `HERDR_NAV_PASSTHROUGH_RE='^(lazygit|k9s)$'` if those tools are commonly used inside Herdr panes; otherwise leave it unset until a conflict appears.
