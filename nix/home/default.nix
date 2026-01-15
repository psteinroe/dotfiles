{ config, lib, pkgs, ... }:

let
  dotfiles = "/Users/psteinroe/Developer/dotfiles";
in
{
  imports = [
    ./packages.nix
    ./shell.nix
    ./git.nix
  ];

  home = {
    username = lib.mkForce "psteinroe";
    homeDirectory = lib.mkForce "/Users/psteinroe";
    stateVersion = "24.11";

    # Install Python tools via uv (runs only on rebuild, not every shell)
    activation.uvTools = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${pkgs.uv}/bin/uv tool install ty --quiet 2>/dev/null || true
      ${pkgs.uv}/bin/uv tool install ruff --quiet 2>/dev/null || true
    '';

    # Install Rust tools via cargo (runs only on rebuild, not every shell)
    activation.cargoTools = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if command -v cargo >/dev/null 2>&1; then
        cargo install jj-ryu --quiet 2>/dev/null || true
      fi
    '';

    # Symlink configs into existing directories (atuin/jj create their own dirs)
    activation.configSymlinks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "$HOME/.config/atuin" "$HOME/.config/jj"
      ln -sf "${dotfiles}/atuin.toml" "$HOME/.config/atuin/config.toml"
      ln -sf "${dotfiles}/jj.toml" "$HOME/.config/jj/config.toml"
    '';
  };

  # Let Home Manager manage itself
  programs.home-manager.enable = true;

  # XDG config files (symlinked for fast iteration)
  # Note: atuin/jj use activation script (their dirs have other files)
  xdg.configFile = {
    "nvim".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/nvim";
    "ghostty/config".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/ghostty.conf";
    "starship.toml".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/starship.toml";
  };

  # Home directory files (symlinked for fast iteration)
  home.file = {
    ".gitconfig".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/gitconfig";
    ".ripgreprc".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/ripgrep";
    # zshrc is managed by home-manager (shell.nix) - sources zsh/*.zsh files

    # Lazygit (macOS path)
    "Library/Application Support/lazygit/config.yml".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/lazygit.yml";

    # Claude (individual files - settings.json excluded, Claude overwrites symlinks)
    ".claude/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/CLAUDE.md";
    ".claude/skills".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/skills";
    ".claude/hooks".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/hooks";
  };
}
