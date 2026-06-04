# Plan: Clean Cross-Platform Dotfiles + Linux Remote Bootstrap

## Goal

Refactor this repo in one pass into a clean cross-platform architecture that supports:

- macOS local machine via `nix-darwin` + Home Manager
- Linux remote servers via standalone Home Manager
- generic Linux remote config, with exe.dev as the first test target
- Determinate Nix as the Nix installer on both platforms
- username always `psteinroe`
- normal remote dev workflow with zsh, Neovim, git, LSPs, CLIs, and agent configs
- reconnectable remote terminal sessions with tmux as an invisible remote persistence layer

This is not a compatibility-layer migration. The end state should be a first-class platform split.

## Target Remote Experience

On a fresh Linux remote machine, including exe.dev:

```sh
curl -fsSL https://raw.githubusercontent.com/psteinroe/dotfiles/main/bootstrap-remote.sh | bash
```

or, after cloning manually:

```sh
~/Developer/dotfiles/bootstrap-remote.sh
```

Expected result:

- user `psteinroe` exists
- Determinate Nix is installed
- dotfiles are cloned to `~/Developer/dotfiles`
- Home Manager applies the Linux config
- shell is zsh
- Neovim works
- CLI tools are installed through Nix
- remote worktree sessions can be reattached without manual tmux commands

## exe.dev Devbox Model

The target state is **one generic Linux remote VM**, not clone-per-task.

The Nix/Home Manager config should stay generic. exe.dev is only the first provider used to host that generic remote VM.

Relevant exe.dev behavior from the docs:

- VMs are real Linux machines with root, apt, systemd, SSH, persistent disk, and auto-stop/resume
- GitHub access can be provided through exe.dev's GitHub App/proxy instead of tokens or PATs on the VM
- exe.dev also supports fast copy-on-write `cp`, but that is not the default workflow for this setup

Recommended exe.dev workflow:

```sh
# create one long-lived generic remote dev VM
ssh exe.dev new dev --image exeuntu
ssh dev.exe.xyz 'curl -fsSL https://raw.githubusercontent.com/psteinroe/dotfiles/main/bootstrap-remote.sh | bash'

# connect from local Ghostty tabs to different worktrees on the same VM
rdev dotfiles linux-remote
rdev app feature-a
rdev app feature-b
```

Target model:

- one VM named/aliased `dev`
- one Nix/Home Manager environment
- many repos/worktrees under `~/Developer`
- many remote tmux sessions, one per repo/worktree
- many local Ghostty tabs can attach to those sessions in parallel

`ssh exe.dev cp ...` remains an optional escape hatch for unusually risky experiments, but it is not part of the primary architecture or helper design.

GitHub integration notes:

- Do not require GitHub PATs or private keys on exe.dev boxes.
- Keep bootstrap able to clone public dotfiles over HTTPS.
- If dotfiles or project repos are private, use exe.dev integration clone URLs such as:

```sh
git clone https://<integration>.int.exe.xyz/<owner>/<repo>.git
```

- For `gh` against an exe.dev integration, set `GH_HOST` to the integration hostname, e.g.:

```sh
export GH_HOST=<integration>.int.exe.xyz
gh repo view <owner>/<repo>
```

This may need repo-specific configuration because exe.dev integrations are per repo/integration hostname, not necessarily one universal GitHub host.

## Remote Session Strategy

SSH alone cannot preserve an interactive shell/Neovim session after disconnect. Something has to own the long-lived terminal session on the server.

Preferred solution: **remote tmux, hidden behind local helper commands**.

Why:

- actively maintained and ubiquitous
- reliable with Neovim
- runs only on the remote machine
- keeps zsh/Neovim alive when a local Ghostty tab closes
- named sessions map naturally to repo/worktree pairs
- no tmux commands need to be typed manually in normal use

Desired behavior:

- plain `ssh dev` remains a plain remote shell
- `rdev <repo> <worktree>` opens/reattaches a persistent remote tmux session
- each local Ghostty tab can attach to a different remote worktree session
- closing a Ghostty tab detaches SSH but leaves the remote tmux session alive
- reopening the same `rdev` command resumes the same zsh/Neovim state

Remote command shape:

```sh
cd ~/Developer/<repo>.git/<worktree>
exec tmux new-session -A -s <repo>-<worktree> -c ~/Developer/<repo>.git/<worktree>
```

Minimal remote tmux config should make tmux feel invisible:

```tmux
set -g status off
set -g mouse off
set -g escape-time 10
set -g focus-events on
set -g default-terminal "tmux-256color"
set -as terminal-overrides ',xterm-256color:RGB,screen-256color:RGB,tmux-256color:RGB'
```

Add `tmux` to Linux packages. It is fine to install on macOS too for local testing, but the remote workflow uses server-side tmux.

## Desired Architecture

```text
nix/
  hosts/
    darwin-psteinroe.nix
    linux-remote.nix
  darwin/
    default.nix
    homebrew.nix
    system.nix
  home/
    default.nix
    common.nix
    darwin.nix
    linux.nix
    packages.nix
    shell.nix
    git.nix
    agents.nix
    remote-skills.nix
```

Principles:

- `nix/home/common.nix` contains only portable Home Manager config.
- `nix/home/darwin.nix` contains macOS-only home files/config.
- `nix/home/linux.nix` contains Linux-only home files/config.
- `nix/darwin/*` remains only for nix-darwin system settings.
- Platform differences are explicit module choices, not scattered path hacks.
- Provider differences are not encoded in Nix unless unavoidable; exe.dev is only a bootstrap/test target.
- Username is always `psteinroe`.
- Home directory is platform-derived:
  - Darwin: `/Users/psteinroe`
  - Linux: `/home/psteinroe`
- Dotfiles path is platform-derived:
  - Darwin: `/Users/psteinroe/Developer/dotfiles`
  - Linux: `/home/psteinroe/Developer/dotfiles`

## Flake Outputs

Expose both first-class outputs:

```text
darwinConfigurations.psteinroe
homeConfigurations."psteinroe@linux-x86_64"
```

Optional future outputs:

```text
homeConfigurations."psteinroe@linux-aarch64"
```

The generic `psteinroe@linux-x86_64` output is the default remote target. Add/use `psteinroe@linux-aarch64` only for ARM remotes.

## Implementation Steps

### 1. Rewrite `flake.nix` around hosts

Create shared host metadata:

```nix
username = "psteinroe";
darwinSystem = "aarch64-darwin";
linuxSystem = "x86_64-linux";
```

Add a helper for Linux Home Manager:

```nix
mkHome = { system, homeDirectory, modules ? [ ] }:
  home-manager.lib.homeManagerConfiguration {
    pkgs = import nixpkgs {
      inherit system;
      overlays = [ inputs.rust-overlay.overlays.default ];
    };
    extraSpecialArgs = {
      inherit inputs system username homeDirectory;
      dotfilesPath = "${homeDirectory}/Developer/dotfiles";
      isDarwin = false;
      isLinux = true;
    };
    modules = [ ./nix/home ] ++ modules;
  };
```

Keep `darwinConfigurations.psteinroe`, but pass the same normalized args into Home Manager.

Acceptance criteria:

```sh
nix flake show
```

shows both Darwin and Linux outputs.

### 2. Refactor Home Manager entrypoint

Change `nix/home/default.nix` from a full config module into an import orchestrator.

It should import:

```nix
./common.nix
./packages.nix
./shell.nix
./git.nix
./agents.nix
```

and then conditionally import:

```nix
./darwin.nix
./linux.nix
```

based on `isDarwin` / `isLinux`.

Remove hardcoded `lib.mkForce "psteinroe"` and `/Users/psteinroe` from the current module. The flake should supply these values.

### 3. Create `nix/home/common.nix`

Move portable config here:

- `home.username`
- `home.homeDirectory`
- `home.stateVersion`
- Home Manager self-management
- Neovim config symlink
- starship config symlink
- atuin config symlink
- tuicr config symlink
- ripgrep config symlink
- npm prefix config
- Python tool activation
- shell completion activation

Use `dotfilesPath` instead of reconstructing the path from home directory inside every module.

### 4. Create `nix/home/darwin.nix`

Move macOS-only home config here:

- Ghostty config symlink
- AeroSpace config symlink
- macOS lazygit config path:
  - `Library/Application Support/lazygit/config.yml`
- macOS SSH config if it keeps using `UseKeychain yes`
- any macOS-specific home files

### 5. Create `nix/home/linux.nix`

Linux-specific config should include:

- Linux lazygit config path:
  - `.config/lazygit/config.yml`
- Linux SSH config without `UseKeychain yes`
- optional `.hushlogin`
- minimal tmux config for invisible remote session persistence
- generic Linux remote conveniences only; keep provider-specific behavior in bootstrap/docs, not Nix modules

Prefer generating Linux SSH config from Nix rather than symlinking the macOS `ssh_config`.

### 6. Refactor package selection

Keep core packages portable:

- bat, eza, tree, wget, curl, htop
- ripgrep, fd
- node, go, lua, elixir, rust toolchain
- uv
- neovim, tree-sitter
- jq, yq, postgresql, just, cmake, ffmpeg, imagemagick
- pnpm, bun
- formatters and LSPs
- git-town, diffnav, gh tooling
- AI CLIs that build on Linux

Add Linux remote package:

- `tmux`

Guard platform-specific packages if needed:

- `tailscale` may be useful on Linux but setup differs from macOS
- external flake packages must be checked for `x86_64-linux`
- anything that fails Linux evaluation should be explicitly platform-gated, not hidden behind shell hacks

Acceptance criteria:

```sh
nix build .#homeConfigurations."psteinroe@linux-x86_64".activationPackage
```

works on a Linux machine.

### 7. Refactor shell config cleanly

Current `zsh/*.zsh` files contain macOS assumptions. Make them platform-aware in the shell files or split them.

Required fixes:

- only add `/opt/homebrew` on Darwin
- only use `$HOME/Library/...` on Darwin
- avoid macOS Keychain helpers on Linux
- make `rebuild` choose the correct command:
  - Darwin: `darwin-rebuild switch --flake ~/Developer/dotfiles#psteinroe`
  - Linux: `home-manager switch --flake ~/Developer/dotfiles#psteinroe@linux-x86_64`
- make `coffee` no-op or Linux-specific
- do not auto-attach plain SSH sessions
- provide remote-dev helpers that attach tmux sessions explicitly per repo/worktree

Acceptance criteria:

```sh
zsh -lic 'echo shell-ok'
```

works on both platforms.

### 8. SSH config split

Do not use one shared SSH config for both platforms if it requires conditionals OpenSSH cannot portably handle.

Recommended files:

```text
ssh_config        # Darwin/current local config
ssh_config.linux  # Linux remote config
```

Darwin can keep:

- OrbStack include
- `UseKeychain yes`
- `AddKeysToAgent yes`

Linux should use:

- `AddKeysToAgent yes` if available
- no `UseKeychain`
- no OrbStack include

Acceptance criteria:

```sh
ssh -G github.com >/dev/null
```

works on Linux.

### 9. Shared Git config

Use one shared `gitconfig` for both platforms now that editor, diff, merge, and credential config are portable.

Shared defaults:

- editor: `nvim`
- merge tool: `nvim`
- credential helper: `!gh auth git-credential`

Linux should not reference macOS-only GUI tools or commands.

Acceptance criteria:

```sh
git config --list --show-origin
```

does not show invalid platform commands.

### 10. Agent config portability

Review and split/guard:

- Claude `caffeinate` hook
- Pi settings with Ghostty-themed assumptions
- any hardcoded `/Users/...` paths
- any scripts using macOS commands

Desired behavior:

- agent configs install on Linux
- macOS-only hooks are not deployed on Linux
- Pi keep-awake extension remains Darwin-guarded
- all paths resolve under `/home/psteinroe` on Linux

Acceptance criteria:

```sh
claude --version
codex --version
opencode --version
pi --version
```

or equivalent startup checks do not fail due to platform-only config.

### 11. Neovim Linux validation

Known things to inspect:

- hardcoded `~/Developer/dotfiles/bin/cpi`
- hardcoded local plugin `~/Developer/review.nvim.git/main`
- Rust DAP/codelldb assumptions
- shell commands that assume macOS

Acceptance criteria:

```sh
nvim --headless '+Lazy! sync' +qa
nvim --headless '+checkhealth' +qa
```

No critical startup failures.

### 12. Linux remote bootstrap

Use `bootstrap-remote.sh` for generic Linux remotes, with exe.dev as the first real test target.

Requirements:

- works when invoked as root, which is expected on many remote providers including exe.dev
- creates user `psteinroe`
- installs base apt packages when `apt` exists
- installs Determinate Nix:

```sh
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install linux --no-confirm
```

- uses `--init none` only if systemd is absent
- generates SSH key for `psteinroe`
- does not require GitHub CLI auth by default; on exe.dev prefer the GitHub integration/proxy and public HTTPS dotfiles clone
- optionally authenticates GitHub CLI interactively on generic remotes when `GITHUB_AUTH=1`
- clones dotfiles to `/home/psteinroe/Developer/dotfiles`
- applies:

```sh
nix run nixpkgs#home-manager -- switch --flake /home/psteinroe/Developer/dotfiles#psteinroe@linux-x86_64
```

### 13. Remote worktree helpers

The local workflow should support opening multiple Ghostty tabs, each attached to a different remote worktree.

Add local helper functions/scripts, probably under `zsh/functions` or `bin`:

```text
rdev       # attach/create remote tmux session on default host for a repo worktree
rdev-host  # attach/create remote tmux session on an explicit host
rwtclone   # run wtclone on the remote
rwtcreate  # run wtcreate on the remote, then attach to the new worktree
rwtcheckout # run wtcheckout on the remote, then attach to that worktree
rwtlist    # list/select remote worktrees, then attach
rwtclean   # run remote wtclean
```

Proposed UX:

```sh
rdev dotfiles linux-remote
rwtclone git@github.com:org/app.git app
rwtcreate app feature-x
rwtcheckout app 123
rwtlist app
rwtclean app
```

Remote repository layout should mirror the existing local worktree workflow:

```text
~/Developer/<repo>.git/<worktree>
```

`rdev <repo> <worktree>` should delegate to `rdev-host ${RDEV_HOST:-dev} <repo> <worktree>`.

`rdev-host <host> <repo> <worktree>` should:

1. derive the remote path: `~/Developer/<repo>.git/<worktree>`
2. derive a safe tmux session name: `<repo>-<worktree>` with slashes replaced
3. SSH to the explicit remote host with a TTY
4. `cd` into the worktree
5. execute `tmux new-session -A -s <session> -c <path>`

Sketch:

```sh
rdev-host() {
  local host="$1"
  local repo="$2"
  local worktree="$3"
  local session="${repo}-${worktree}"
  session="${session//\//-}"
  local dir="~/Developer/${repo}.git/${worktree}"

  ssh -t "$host" "cd $dir && exec tmux new-session -A -s '$session' -c $dir"
}

rdev() {
  rdev-host "${RDEV_HOST:-dev}" "$@"
}
```

Remote worktree helper strategy:

- keep the canonical `wtclone`, `wtcreate`, `wtcheckout`, `wtlist`, and `wtclean` implementation on the remote too via the same dotfiles
- local `rwt*` wrappers should call the remote `wt*` functions inside zsh, then attach the relevant tmux session
- avoid duplicating git-worktree logic separately on local and remote
- make host configurable via `RDEV_HOST`, defaulting to `dev`

Open design point:

- `rwtlist` needs remote selection. Either:
  1. run remote `wtselect` over SSH using the local terminal TTY, or
  2. return machine-readable worktree paths from the remote and run local `fzf`, then attach.

Prefer option 2 if latency makes remote `fzf` feel bad; otherwise option 1 is simpler.

Acceptance criteria:

- two local Ghostty tabs can run two different `rdev` sessions concurrently
- closing a tab does not kill the remote shell/Neovim
- reopening the same `rdev` resumes the same session
- local `rwtcreate`/`rwtcheckout` can create/select a remote worktree and attach to it

### 14. Documentation

Update `README.md` with separate install paths.

macOS:

```sh
curl -fsSL https://raw.githubusercontent.com/psteinroe/dotfiles/main/bootstrap.sh | bash
```

Linux remote, including exe.dev:

```sh
curl -fsSL https://raw.githubusercontent.com/psteinroe/dotfiles/main/bootstrap-remote.sh | bash
```

Manual Linux:

```sh
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install linux --no-confirm
git clone https://github.com/psteinroe/dotfiles.git ~/Developer/dotfiles
nix run nixpkgs#home-manager -- switch --flake ~/Developer/dotfiles#psteinroe@linux-x86_64
```

Remote reconnect UX:

```sh
rdev dotfiles linux-remote
# attaches to remote tmux session dotfiles-linux-remote in ~/Developer/dotfiles.git/linux-remote
```

Plain SSH remains plain:

```sh
ssh dev
```

## Validation Checklist

On macOS:

```sh
darwin-rebuild switch --flake ~/Developer/dotfiles#psteinroe
zsh -lic 'echo shell-ok'
nvim --headless '+checkhealth' +qa
```

On Linux remote:

```sh
/home/psteinroe/Developer/dotfiles/bootstrap-remote.sh
nix run nixpkgs#home-manager -- switch --flake ~/Developer/dotfiles#psteinroe@linux-x86_64
zsh -lic 'echo shell-ok'
ssh -G github.com >/dev/null
git config --list --show-origin
nvim --headless '+Lazy! sync' +qa
nvim --headless '+checkhealth' +qa
```

Session persistence test:

1. Run `rdev dotfiles linux-remote` from a local Ghostty tab.
2. Open Neovim in the remote worktree.
3. Close the local Ghostty tab.
4. Run `rdev dotfiles linux-remote` again.
5. Confirm the same remote tmux session and Neovim instance are still there.
6. Open a second Ghostty tab with a different `rdev` repo/worktree and confirm both sessions run independently.

## Risks

- Some external flake packages may not expose `x86_64-linux` packages.
- Claude/Codex/Pi packages may evaluate differently on Linux.
- Agent hooks may still contain hidden Darwin assumptions.
- Git signing and GitHub auth may need Linux-specific setup.
- remote providers may have machine-specific constraints despite exposing root, apt, and systemd.

## Definition of Done

- macOS rebuild still works.
- generic Linux bootstrap works from a fresh exe.dev test machine.
- `psteinroe@linux-x86_64` Home Manager output builds and switches.
- zsh starts cleanly on both platforms.
- Neovim starts cleanly on both platforms.
- SSH and git configs are platform-correct.
- `rdev`/`rwt*` helpers give persistent remote worktree sessions without manual tmux management.
- README documents both macOS and Linux flows.
