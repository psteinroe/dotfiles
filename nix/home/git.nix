{ pkgs, ... }:

{
  # Just enable the programs - configs are symlinked from dotfiles
  programs.git = {
    enable = true;
    delta = {
      enable = true;
    };
  };

  programs.gh.enable = true;

  programs.lazygit.enable = true;
}
