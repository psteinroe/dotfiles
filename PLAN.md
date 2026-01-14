# Dotfiles: Nix-Darwin + Home Manager Migration

## Overview

Migrate from Dotbot + Brewfile + shell scripts → **nix-darwin + Home Manager** with single `flake.nix` entry point.

---

## Quick Start (New Machine - Post Migration)

```bash
# One command (after setting up SSH key for GitHub)
curl -fsSL https://raw.githubusercontent.com/psteinroe/dotfiles/main/scripts/bootstrap.sh | bash
```

Or manually:
```bash
# 1. Install Nix
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# 2. Clone dotfiles
git clone git@github.com:psteinroe/dotfiles.git ~/.dotfiles
cd ~/.dotfiles

# 3. Build and switch
nix run nix-darwin -- switch --flake .
```

---

## Key Flake Inputs

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  nix-darwin.url = "github:LnL7/nix-darwin";
  home-manager.url = "github:nix-community/home-manager";
  nix-homebrew.url = "github:zhaofengli/nix-homebrew";

  # GUI apps as nix derivations (no Homebrew needed)
  nix-casks.url = "github:atahanyorganci/nix-casks";

  # Claude Code (hourly updates)
  claude-code.url = "github:sadjow/claude-code-nix";

  # Ghostty config management (binary via Homebrew)
  ghostty-hm-module.url = "github:clo4/ghostty-hm-module";
};
```

---

## Target Directory Structure

```
~/.dotfiles/
├── flake.nix                    # Single entry point
├── flake.lock                   # Auto-generated lockfile
├── nix/
│   ├── darwin/
│   │   ├── default.nix          # nix-darwin system config
│   │   ├── homebrew.nix         # Declarative Homebrew (casks only)
│   │   └── system.nix           # Dock, Finder, keyboard settings
│   └── home/
│       ├── default.nix          # Home Manager entry point
│       ├── shell.nix            # zsh + starship + atuin + fzf + zoxide
│       ├── git.nix              # Git + delta + gh + lazygit
│       └── packages.nix         # CLI packages from Nix
│
├── # === EXISTING FILES (symlinked or sourced) ===
├── zshrc.local                  # Custom zsh functions (renamed from zshrc)
├── nvim/                        # Neovim config (symlinked)
├── ghostty/                     # Ghostty config (symlinked)
├── claude/                      # Claude config (symlinked)
│
├── scripts/
│   └── bootstrap.sh             # One-command bootstrap
└── setup/                       # Archive (keep for reference)
```

---

## Changes from Current Setup

### Remove
- tmux, tmuxinator (not needed)
- nvm → use nix nodejs + per-project flakes
- pyenv → use uv
- java setup (not needed for now)
- diff-so-fancy (keep git-delta only)
- flyctl, infisical (not needed)
- ghostscript (not needed)
- vhs (not needed)
- vscode, cursor (not needed)
- android-studio (not needed)
- kitty → use ghostty only
- notion, homerow, steam, vivid, garmin-express, expo-orbit (not needed)
- eloston-chromium → use google-chrome
- cargo install / pnpm install -g → manage via nix
- bob-nvim → use nix neovim
- Mason.nvim → use nix-managed LSPs

### Add
- claude (CLI)
- nodejs (global via nix)
- neovim (via nix)
- All LSPs via nix (not Mason)

---

## Package Distribution

### Nix (nixpkgs) - CLI Tools

**Shell:**
- zsh, starship, atuin, zoxide, fzf, bat, eza

**Search:**
- ripgrep, fd

**Git:**
- git, gh, lazygit, delta

**Languages:**
- nodejs (global LTS)
- go, rustup, lua, elixir, ruby
- uv (Python)

**Editor:**
- neovim (via nix, not bob)

**Dev Tools:**
- jq, yq, just, hugo, cmake, ffmpeg, awscli
- stylua, shfmt (formatters)
- pnpm (for project-local deps)

**LSPs (via nix, not Mason):**
- lua-language-server
- vscode-langservers-extracted (html, css, json, eslint)
- typescript-language-server
- tailwindcss-language-server
- dockerfile-language-server
- yaml-language-server
- nil (nix LSP)
- gopls
- rust-analyzer

**Linters/Formatters:**
- eslint_d
- prettierd
- stylua
- shfmt
- golangci-lint

**Rust Tools (via nix):**
- cargo-expand, cargo-insta
- git-stack

### Nix (claude-code-nix) - Claude CLI

```nix
# Via flake input
inputs.claude-code.packages.${system}.default
```

### Nix (nix-casks) - GUI Apps

**Communication:**
- slack, discord

**Productivity:**
- raycast, bitwarden, stats, timing, linear

**Networking:**
- tailscale

**Development:**
- bruno, orbstack

**Media:**
- spotify

**Browser:**
- google-chrome

**Fonts:**
- font-fira-code-nerd-font

```nix
# Via flake input
inputs.nix-casks.packages.${system}.slack
inputs.nix-casks.packages.${system}.raycast
# etc.
```

### Homebrew (minimal - only what nix can't do)

**Casks:**
- ghostty (nixpkgs broken on Darwin, needs signed binary)
- logitech-options (.pkg installer, hardware driver)

**Brews:**
- mas (Mac App Store CLI)
- cocoapods, fastlane, watchman (iOS dev - macOS specific)
- graphite (not in nixpkgs)

### Mac App Store (via mas)

- Xcode
- WhatsApp

---

## Implementation Phases

### Phase 1: Foundation

Create `flake.nix`:
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # GUI apps as nix derivations
    nix-casks = {
      url = "github:atahanyorganci/nix-casks";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Claude Code CLI
    claude-code = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Ghostty config management
    ghostty-hm-module.url = "github:clo4/ghostty-hm-module";
  };
  # ...
}
```

Create `nix/darwin/default.nix`:
- Enable nix-daemon
- Set system state version
- Import homebrew.nix and system.nix

Create `nix/home/default.nix`:
- Set home.stateVersion
- Import shell.nix, git.nix, packages.nix

### Phase 2: Packages (`nix/home/packages.nix`)

```nix
{ pkgs, inputs, system, ... }:

let
  nix-casks = inputs.nix-casks.packages.${system};
  claude-code = inputs.claude-code.packages.${system};
in {
  home.packages = with pkgs; [
    # Shell
    starship atuin zoxide fzf bat eza

    # Search
    ripgrep fd

    # Git
    gh lazygit delta

    # Languages
    nodejs_22  # Global Node.js LTS
    go lua elixir ruby
    rustup

    # Python
    uv

    # Editor
    neovim

    # Tools
    jq yq just hugo cmake ffmpeg awscli
    pnpm

    # Formatters
    stylua shfmt prettierd

    # LSPs
    lua-language-server
    nodePackages.vscode-langservers-extracted
    nodePackages.typescript-language-server
    nodePackages."@tailwindcss/language-server"
    nodePackages.dockerfile-language-server-nodejs
    nodePackages.yaml-language-server
    nil  # Nix LSP
    gopls
    rust-analyzer

    # Linters
    nodePackages.eslint_d
    golangci-lint

    # Rust tools
    cargo-expand cargo-insta

    # Claude Code (via claude-code-nix)
    claude-code.default

    # GUI Apps (via nix-casks)
    nix-casks.slack
    nix-casks.discord
    nix-casks.raycast
    nix-casks.bitwarden
    nix-casks.stats
    nix-casks.timing
    nix-casks.linear
    nix-casks.bruno
    nix-casks.orbstack
    nix-casks.spotify
    nix-casks.google-chrome
    nix-casks.font-fira-code-nerd-font
    nix-casks.tailscale
  ];
}
```

### Phase 3: Shell Configuration (`nix/home/shell.nix`)

**Minimal nix config** - configs stay in dotfiles, symlinked via Phase 5:

```nix
{
  # Just enable the programs - configs are symlinked
  programs.zsh.enable = true;
  programs.starship.enable = true;  # Config: starship.toml
  programs.atuin.enable = true;     # Config: atuin/
  programs.zoxide.enable = true;
  programs.fzf.enable = true;
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
```

**Note**: All settings stay in existing config files (starship.toml, atuin/config.toml, zshrc)

### Phase 4: Git Configuration (`nix/home/git.nix`)

**Minimal nix config** - configs stay in dotfiles, symlinked via Phase 5:

```nix
{
  # Just enable the programs - configs are symlinked
  programs.git.enable = true;     # Config: gitconfig
  programs.gh.enable = true;
  programs.lazygit.enable = true; # Config: lazygit.yml
}
```

**Note**: All settings stay in existing config files (gitconfig, lazygit.yml)

### Phase 5: Symlinks (`nix/home/default.nix`)

**All configs stay as files, symlinked for fast iteration:**

```nix
{ config, ... }:

let
  dotfiles = "/Users/psteinroe/.dotfiles";
in {
  # XDG config files
  xdg.configFile = {
    "nvim".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/nvim";
    "ghostty".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/ghostty";
    "starship.toml".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/starship.toml";
    "atuin".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/atuin";
  };

  # Home directory files
  home.file = {
    ".gitconfig".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/gitconfig";
    ".ripgreprc".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/ripgrep";
    ".zshrc".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/zshrc";
    ".wakatime.cfg".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/.wakatime.cfg";

    # Lazygit (macOS path)
    "Library/Application Support/lazygit/config.yml".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/lazygit.yml";

    # Claude
    ".claude".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude";
  };
}
```

### Phase 6: System Settings (`nix/darwin/system.nix`)

```nix
system.defaults.dock = {
  autohide = false;
  show-recents = false;
  persistent-apps = [
    "/Applications/Safari.app"
    "/System/Applications/Mail.app"
    "/System/Applications/Calendar.app"
    "/Applications/Slack.app"
    "/Applications/Ghostty.app"
    "/Applications/Linear.app"
    "/Applications/Spotify.app"
    "/System/Applications/System Settings.app"
  ];
};

system.defaults.finder = {
  AppleShowAllExtensions = true;
  ShowPathbar = true;
};

system.defaults.NSGlobalDomain = {
  AppleInterfaceStyle = "Dark";
  KeyRepeat = 2;
  InitialKeyRepeat = 15;
};

# Disable desktop widgets
system.defaults.CustomUserPreferences = {
  "com.apple.WindowManager" = {
    StandardHideWidgets = 1;      # Hide widgets on desktop
    StageManagerHideWidgets = 1;  # Hide widgets in Stage Manager
  };
};

# Screensaver
system.defaults.screensaver = {
  askForPassword = true;
  askForPasswordDelay = 0;  # Require password immediately
};

# Wallpaper (no built-in option, use activation script)
system.activationScripts.postActivation.text = ''
  osascript -e 'tell application "System Events" to tell every desktop to set picture to "/Users/psteinroe/.dotfiles/media/wallpaper.jpg" as POSIX file'
'';
```

### Phase 7: Homebrew (`nix/darwin/homebrew.nix`)

Minimal Homebrew - only what nix can't handle:

```nix
homebrew = {
  enable = true;
  onActivation.cleanup = "zap";

  taps = [ "withgraphite/tap" ];

  # macOS-specific CLIs
  brews = [
    "mas"       # Mac App Store CLI
    "graphite"  # Not in nixpkgs

    # iOS development
    "cocoapods"
    "fastlane"
    "watchman"
  ];

  # Only apps that can't be nix-casks
  casks = [
    "ghostty"          # nixpkgs broken on Darwin, needs signed binary
    "logitech-options" # .pkg installer, hardware driver
  ];

  masApps = {
    "Xcode" = 497799835;
    "WhatsApp" = 310633997;
  };
};
```

**Note:** Most GUI apps moved to nix-casks (slack, discord, raycast, etc.)

### Phase 8: Bootstrap Script (`scripts/bootstrap.sh`)

```bash
#!/bin/bash
set -e

echo "=== psteinroe dotfiles bootstrap ==="

# Install Xcode CLI tools (needed for git)
if ! xcode-select -p &>/dev/null; then
  echo "Installing Xcode Command Line Tools..."
  xcode-select --install
  echo "Press enter after Xcode tools are installed..."
  read
fi

# Install Nix
if ! command -v nix &>/dev/null; then
  echo "Installing Nix..."
  curl --proto '=https' --tlsv1.2 -sSf -L \
    https://install.determinate.systems/nix | sh -s -- install

  # Source nix in current shell
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# Clone dotfiles
DOTFILES="$HOME/.dotfiles"
if [ ! -d "$DOTFILES" ]; then
  echo "Cloning dotfiles..."
  git clone git@github.com:psteinroe/dotfiles.git "$DOTFILES"
fi

cd "$DOTFILES"

# First run of nix-darwin (bootstraps itself)
echo "Building system configuration..."
nix run nix-darwin -- switch --flake .

echo ""
echo "=== Done! ==="
echo "Your system is configured. Restart your terminal."
echo ""
echo "Future updates: darwin-rebuild switch --flake ~/.dotfiles"
```

### Phase 9: Cleanup

1. Delete obsolete files:
   - `.dotbot.conf.yaml`
   - `install.sh`
   - `Brewfile`
2. Archive `setup/*.sh` (keep for reference)
3. Update README.md

**Keep all config files** (symlinked via nix):
- `zshrc`, `gitconfig`, `starship.toml`, `atuin/`, `lazygit.yml`, `ripgrep`, `nvim/`, `ghostty/`, `claude/`

---

## Critical Files to Create

| File | Purpose |
|------|---------|
| `flake.nix` | Entry point, defines all inputs and darwin config |
| `nix/darwin/default.nix` | nix-darwin system configuration |
| `nix/darwin/homebrew.nix` | Declarative Homebrew casks |
| `nix/darwin/system.nix` | macOS system preferences (Dock, Finder, keyboard) |
| `nix/home/default.nix` | Home Manager entry point + symlinks |
| `nix/home/packages.nix` | Nix packages (replaces Brewfile + cargo + pnpm -g) |
| `nix/home/shell.nix` | Zsh + Starship + Atuin + FZF + Zoxide + Direnv |
| `nix/home/git.nix` | Git + Delta + GH CLI + Lazygit |
| `scripts/bootstrap.sh` | One-command new machine setup |

---

## Config Migration Summary

**Strategy: Keep config files, symlink via nix** (faster iteration, no rebuild needed)

| Config | File | Symlink Target |
|--------|------|----------------|
| Neovim | `nvim/` | `~/.config/nvim` |
| Ghostty | `ghostty/` | `~/.config/ghostty` |
| Starship | `starship.toml` | `~/.config/starship.toml` |
| Atuin | `atuin/` | `~/.config/atuin` |
| Git | `gitconfig` | `~/.gitconfig` |
| Lazygit | `lazygit.yml` | `~/Library/Application Support/lazygit/config.yml` |
| Ripgrep | `ripgrep` | `~/.ripgreprc` |
| Zsh | `zshrc` | `~/.zshrc` |
| Claude | `claude/` | `~/.claude/` |
| WakaTime | `.wakatime.cfg` | `~/.wakatime.cfg` |

---

## Neovim LSP Configuration

With LSPs managed by nix instead of Mason, update nvim config:

```lua
-- In nvim/lua/plugins/lsp.lua
-- Remove mason.nvim and mason-lspconfig.nvim
-- Configure LSPs directly since they're in PATH via nix

local lspconfig = require('lspconfig')

-- LSPs are already installed via nix, just configure them
lspconfig.lua_ls.setup({})
lspconfig.ts_ls.setup({})
lspconfig.gopls.setup({})
lspconfig.rust_analyzer.setup({})
lspconfig.nil_ls.setup({})  -- Nix LSP
lspconfig.tailwindcss.setup({})
lspconfig.eslint.setup({})
lspconfig.jsonls.setup({})
lspconfig.yamlls.setup({})
lspconfig.dockerls.setup({})
```

---

## Daily Usage (Post Migration)

```bash
# Apply configuration changes
darwin-rebuild switch --flake ~/.dotfiles

# Update all inputs (nixpkgs, home-manager, etc.)
nix flake update ~/.dotfiles
darwin-rebuild switch --flake ~/.dotfiles

# Edit neovim config (instant, no rebuild needed)
nvim ~/.dotfiles/nvim/lua/plugins/lsp.lua
```

---

## Manual Post-Install

1. `gh auth login`
2. `atuin login && atuin sync`
3. GPG key import
4. Open nvim (plugins auto-install via lazy.nvim)
5. System Preferences: keyboard repeat, trackpad

---

## Notes

- **Config files stay as-is**: All configs (zshrc, gitconfig, starship.toml, etc.) remain as dotfiles, symlinked via nix. Edit them directly, no rebuild needed.
- **Determinate Nix compatibility**: There's a known issue with nix-darwin. May need to use official Nix installer or check nix-darwin README for workarounds.
- **GPG signing**: Will need `programs.gpg.enable` and pinentry config
- **Per-project Node.js**: Use direnv + flakes for project-specific versions, global nodejs for CLI tools
- **Mason.nvim removal**: Delete mason.nvim, mason-lspconfig.nvim from nvim config; LSPs come from nix PATH
- **Neovim via nix**: Use `pkgs.neovim` instead of bob-nvim; always on latest stable
- **nix-casks limitations**: Doesn't support .pkg installers (logitech-options) or apps requiring special signing (ghostty)
- **Ghostty on Darwin**: [Broken in nixpkgs](https://github.com/NixOS/nixpkgs/issues/388984) due to Xcode/Swift 6 requirements; use Homebrew cask for binary, config symlinked from dotfiles

---

## Sources

- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [nix-darwin + home-manager setup](https://noghartt.dev/blog/set-up-nix-on-macos-using-flakes-nix-darwin-and-home-manager/)
- [nix-homebrew](https://github.com/zhaofengli/nix-homebrew)
- [mkOutOfStoreSymlink for fast iteration](https://seroperson.me/2024/01/16/managing-dotfiles-with-nix/)
- [Determinate Systems Nix installer](https://determinate.systems/posts/determinate-nix-installer)
- [nix-casks](https://github.com/atahanyorganci/nix-casks) - Homebrew casks as nix derivations
- [claude-code-nix](https://github.com/sadjow/claude-code-nix) - Claude Code with hourly updates
- [ghostty-hm-module](https://github.com/clo4/ghostty-hm-module) - Ghostty config for Home Manager
