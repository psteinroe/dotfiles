{ pkgs, ... }:

{
  # Just enable the programs - configs are symlinked from dotfiles
  programs.git.enable = true;

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
  };

  programs.gh.enable = true;

  programs.lazygit.enable = true;
}
