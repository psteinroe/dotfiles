{ config, ... }:

let
  username = "psteinroe";
  dotfiles = "/Users/${username}/Developer/dotfiles";
in
{
  imports = [
    ./packages.nix
    ./shell.nix
    ./git.nix
  ];

  home = {
    username = username;
    homeDirectory = "/Users/${username}";
    stateVersion = "24.11";
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

    # Claude
    ".claude".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude";
  };
}
