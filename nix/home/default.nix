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
  };

  # Let Home Manager manage itself
  programs.home-manager.enable = true;

  # XDG config files (symlinked for fast iteration)
  xdg.configFile = {
    "nvim".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/nvim";
    "ghostty".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/ghostty";
    "starship.toml".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/starship.toml";
    "atuin".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/atuin";
  };

  # Home directory files (symlinked for fast iteration)
  home.file = {
    ".gitconfig".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/gitconfig";
    ".ripgreprc".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/ripgrep";
    ".zshrc".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/zshrc";
    ".wakatime.cfg".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/.wakatime.cfg";

    # Lazygit (macOS path)
    "Library/Application Support/lazygit/config.yml".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/lazygit.yml";

    # Claude (individual files, not whole directory)
    ".claude/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/CLAUDE.md";
    ".claude/skills".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/skills";
    ".claude/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/settings.json";
  };
}
