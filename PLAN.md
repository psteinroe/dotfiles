     # Migration Plan: Dotfiles to nix-darwin + Home Manager

     ## Overview
     Migrate from Dotbot + Brewfile + shell scripts to a fully declarative nix-darwin
      + Home Manager setup with a single `flake.nix` entry point.

     ---

     ## Directory Structure

     ```
     ~/.dotfiles/
     ├── flake.nix                    # Single entry point
     ├── flake.lock                   # Auto-generated lockfile
     ├── hosts/
     │   └── darwin/
     │       ├── default.nix          # nix-darwin system config
     │       ├── homebrew.nix         # Declarative Homebrew (casks only)
     │       └── system.nix           # Dock, Finder, keyboard settings
     ├── home/
     │   ├── default.nix              # Home Manager entry point
     │   ├── shell.nix                # zsh (hybrid) + starship + atuin + fzf +
     zoxide
     │   ├── git.nix                  # Git + delta + gh + lazygit
     │   └── packages.nix             # CLI packages from Nix
     │
     ├── # === EXISTING FILES (symlinked or sourced) ===
     ├── zshrc.local                  # Custom zsh functions (renamed from zshrc)
     ├── nvim/                        # Neovim config (symlinked)
     ├── ghostty/                     # Ghostty config (symlinked)
     │
     ├── scripts/
     │   └── bootstrap.sh             # One-command bootstrap
     └── setup/                       # Archive (keep for reference)
     ```

     ---

     ## Implementation Steps

     ### Phase 1: Foundation
     1. Create `flake.nix` with inputs:
        - nixpkgs (unstable)
        - nix-darwin
        - home-manager (as darwin module)
        - nix-homebrew

     2. Create `hosts/darwin/default.nix`:
        - Enable nix-daemon
        - Set system state version
        - Import homebrew.nix and system.nix

     3. Create `home/default.nix`:
        - Set home.stateVersion
        - Import shell.nix, git.nix, packages.nix

     ### Phase 2: Packages Migration
     1. Create `home/packages.nix` with CLI tools:
        - ripgrep, fd, fzf, bat, eza, jq, yq
        - git, gh, lazygit, delta
        - starship, atuin, zoxide
        - neovim, lua, go, rustup
        - ffmpeg, imagemagick, hugo, just
        - awscli2, flyctl, cmake

     2. Create `hosts/darwin/homebrew.nix`:
        - Casks: VS Code, Cursor, Slack, Discord, Raycast, Spotify, Ghostty, etc.
        - Brews: nvm, cocoapods, fastlane, mas
        - masApps: Xcode, WhatsApp

     ### Phase 3: Shell Configuration (`home/shell.nix`)
     **Hybrid approach**: Nix handles tool integrations, custom functions stay in
     `zshrc.local`

     ```nix
     programs.zsh = {
       enable = true;
       enableCompletion = true;
       syntaxHighlighting.enable = true;
       autosuggestion.enable = true;
       initExtra = ''
         source ${dotfiles}/zshrc.local  # Your custom functions
       '';
     };

     programs.starship = {
       enable = true;
       settings = {
         add_newline = false;
         battery.display = [
           { threshold = 10; style = "bold red"; }
           { threshold = 30; style = "bold yellow"; }
         ];
       };
     };

     programs.atuin = {
       enable = true;
       settings = {
         keymap_mode = "vim-insert";
         search_mode = "fuzzy";
         filter_mode = "workspace";
         # ... full config inline
       };
     };

     programs.zoxide.enable = true;
     programs.fzf.enable = true;
     programs.direnv = { enable = true; nix-direnv.enable = true; };
     ```

     **Action**: Rename `zshrc` → `zshrc.local`, remove lines now handled by Nix
     (starship init, atuin init, zoxide init, syntax highlighting setup)

     ### Phase 4: Git Configuration (`home/git.nix`)
     **Full Nix**: Clean key-value config maps well

     ```nix
     programs.git = {
       enable = true;
       userName = "psteinroe";
       userEmail = "philipp@steinroetter.com";
       signing = { key = "C3F5A010"; signByDefault = true; };
       delta = {
         enable = true;
         options = { navigate = true; side-by-side = true; syntax-theme = "Dracula";
     };
       };
       aliases = { undo = "reset --soft HEAD^"; next = "stack next"; /* ... */ };
       extraConfig = { /* merge, diff, push, pull settings */ };
     };

     programs.gh = { enable = true; settings.git_protocol = "ssh"; };

     programs.lazygit = {
       enable = true;
       settings.git.paging = {
         colorArg = "always";
         pager = "delta --dark --paging=never syntax-theme=Dracula";
       };
     };
     ```

     ### Phase 5: Symlinks (`home/default.nix`)
     ```nix
     # Neovim - symlink for fast iteration
     xdg.configFile."nvim".source =
       config.lib.file.mkOutOfStoreSymlink "${dotfiles}/nvim";

     # Ghostty - symlink (no Home Manager module)
     xdg.configFile."ghostty".source =
       config.lib.file.mkOutOfStoreSymlink "${dotfiles}/ghostty";
     ```

     ### Phase 6: System Settings (`hosts/darwin/system.nix`)
     ```nix
     system.defaults.dock = {
       autohide = false;
       show-recents = false;
       persistent-apps = [
         "/Applications/Safari.app"
         "/System/Applications/Mail.app"
         "/Applications/Slack.app"
         "/Applications/Ghostty.app"
         "/Applications/Spotify.app"
       ];
     };

     system.defaults.finder = {
       AppleShowAllExtensions = true;
       ShowPathbar = true;
     };

     system.defaults.NSGlobalDomain = {
       AppleInterfaceStyle = "Dark";
       KeyRepeat = 2;
     };
     ```

     ### Phase 7: Bootstrap & Cleanup
     1. Create `scripts/bootstrap.sh`
     2. Rename `zshrc` → `zshrc.local`
     3. Delete: `tmux.conf`, `kitty/`, `tmux-layouts/`, `.dotbot.conf.yaml`
     4. Archive: `setup/*.sh` (keep for reference)
     5. Update README.md

     ---

     ## Critical Files to Create

     | File | Purpose |
     |------|---------|
     | `flake.nix` | Entry point, defines all inputs and darwin config |
     | `hosts/darwin/default.nix` | nix-darwin system configuration |
     | `hosts/darwin/homebrew.nix` | Declarative Homebrew casks |
     | `hosts/darwin/system.nix` | macOS system preferences (Dock, Finder, keyboard)
     |
     | `home/default.nix` | Home Manager entry point + symlinks |
     | `home/packages.nix` | Nix packages (replaces most of Brewfile) |
     | `home/shell.nix` | Zsh + Starship + Atuin + FZF + Zoxide + Direnv |
     | `home/git.nix` | Git + Delta + GH CLI + Lazygit |
     | `scripts/bootstrap.sh` | One-command new machine setup |

     ---

     ## Package Migration Summary

     **Move to Nix (~55 packages):**
     - Shell: zsh, starship, atuin, zoxide, fzf
     - Search: ripgrep, fd, bat, eza
     - Git: git, gh, lazygit, delta
     - Languages: go, rustup, lua, elixir, ruby, perl
     - Tools: jq, yq, just, hugo, ffmpeg, awscli2, flyctl

     **Keep in Homebrew (casks):**
     - IDEs: VS Code, Cursor, Android Studio
     - Terminal: Ghostty
     - Communication: Slack, Discord, Notion
     - Utilities: Raycast, Bitwarden, Stats
     - Media: Spotify, Steam
     - Fonts: font-fira-code-nerd-font

     **Keep in Homebrew (brews):**
     - nvm (or migrate to direnv per-project)
     - cocoapods, fastlane, watchman (iOS dev)
     - mas (Mac App Store CLI)

     ---

     ## Bootstrap Command (New Machine)

     ```bash
     # One command to rule them all
     curl -fsSL
     https://raw.githubusercontent.com/psteinroe/dotfiles/main/scripts/bootstrap.sh |
      bash
     ```

     Or manually:
     ```bash
     # 1. Install Nix
     curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix
     | sh -s -- install

     # 2. Clone and apply
     git clone https://github.com/psteinroe/dotfiles.git ~/.dotfiles
     cd ~/.dotfiles
     nix run nix-darwin -- switch --flake .
     ```

     ---

     ## Daily Usage

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

     ## Config Migration Summary

     | Config | Strategy | Old File | New Location |
     |--------|----------|----------|--------------|
     | Git | **Full Nix** | `gitconfig` | `home/git.nix` |
     | Lazygit | **Full Nix** | `lazygit.yml` | `home/git.nix` |
     | Starship | **Full Nix** | `starship.toml` | `home/shell.nix` |
     | Atuin | **Full Nix** | `atuin/config.toml` | `home/shell.nix` |
     | Zsh | **Hybrid** | `zshrc` → `zshrc.local` | `home/shell.nix` sources it |
     | Neovim | **Symlink** | `nvim/` | `mkOutOfStoreSymlink` |
     | Ghostty | **Symlink** | `ghostty/` | `mkOutOfStoreSymlink` |

     ---

     ## Notes

     - **Determinate Nix compatibility**: There's a known issue with nix-darwin. May
     need to use official Nix installer or check nix-darwin README for workarounds.
     - **GPG signing**: Will need `programs.gpg.enable` and pinentry config
     - **Language versions**: Keep nvm initially for Node.js; consider migrating to
     direnv + flakes per-project later
     - **Mason.nvim**: May conflict with Nix-provided LSPs; configure to prefer Nix
     packages
     - **Files to delete**: `tmux.conf`, `kitty/`, `tmux-layouts/`, `starship.toml`,
     `atuin/`, `gitconfig`, `lazygit.yml`, `.dotbot.conf.yaml`

     ---

     ## Sources

     - [Home Manager Manual](https://nix-community.github.io/home-manager/)
     - [nix-darwin + home-manager setup](https://noghartt.dev/blog/set-up-nix-on-maco
     s-using-flakes-nix-darwin-and-home-manager/)
     - [nix-homebrew](https://github.com/zhaofengli/nix-homebrew)
     - [mkOutOfStoreSymlink for fast
     iteration](https://seroperson.me/2024/01/16/managing-dotfiles-with-nix/)
     - [Determinate Systems Nix
     installer](https://determinate.systems/posts/determinate-nix-installer)


BOOTSTRAP:
  We can create scripts/bootstrap.sh that does everything:

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

  Then on a new Mac, you just need:

  # One command (after setting up SSH key for GitHub)
  curl -fsSL https://raw.githubusercontent.com/psteinroe/dotfiles/main/scripts/bootstrap.sh | bash

