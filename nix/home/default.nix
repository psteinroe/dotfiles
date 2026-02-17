{
  config,
  lib,
  pkgs,
  ...
}:

let
  dotfiles = "${config.home.homeDirectory}/Developer/dotfiles";
in
{
  imports = [
    ./packages.nix
    ./shell.nix
    ./git.nix
    ./agents.nix
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

    # Generate shell completions
    activation.completions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p $HOME/.zsh/completions
      ${pkgs.git-town}/bin/git-town completions zsh > $HOME/.zsh/completions/_git-town 2>/dev/null || true
      ${pkgs.just}/bin/just --completions zsh > $HOME/.zsh/completions/_just 2>/dev/null || true
      ${pkgs.gh}/bin/gh completion -s zsh > $HOME/.zsh/completions/_gh 2>/dev/null || true
      ${pkgs.rustup}/bin/rustup completions zsh > $HOME/.zsh/completions/_rustup 2>/dev/null || true
      ${pkgs.rustup}/bin/rustup completions zsh cargo > $HOME/.zsh/completions/_cargo 2>/dev/null || true
      ${pkgs.bun}/bin/bun completions > $HOME/.zsh/completions/_bun 2>/dev/null || true
      ${pkgs.fd}/bin/fd --gen-completions zsh > $HOME/.zsh/completions/_fd 2>/dev/null || true
      ${pkgs.ripgrep}/bin/rg --generate complete-zsh > $HOME/.zsh/completions/_rg 2>/dev/null || true
    '';

  };

  # Let Home Manager manage itself
  programs.home-manager.enable = true;

  # XDG config files (symlinked for fast iteration)
  xdg.configFile = {
    "nvim".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/nvim";
    "ghostty/config".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/ghostty.conf";
    "starship.toml".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/starship.toml";
    "atuin/config.toml".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/atuin.toml";
  };

  # Home directory files (symlinked for fast iteration)
  home.file = {
    ".gitconfig".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/gitconfig";
    ".ripgreprc".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/ripgrep";
    ".ssh/config".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/ssh_config";
    # zshrc is managed by home-manager (shell.nix) - sources zsh/*.zsh files

    # Lazygit (macOS path)
    "Library/Application Support/lazygit/config.yml".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/lazygit.yml";

    # Agent configs (Claude, OpenCode, Codex) managed via agents.nix
  };
}
