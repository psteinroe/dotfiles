{ pkgs, ... }:

{
  # Just install the packages - configs are symlinked from dotfiles
  # gitconfig already has delta config, lazygit.yml is symlinked
  programs.git.enable = true;
  programs.delta.enable = true;  # No enableGitIntegration - gitconfig has it
  programs.gh = {
    enable = true;
    extensions = [ pkgs.gh-poi ];
  };
  programs.lazygit.enable = true;
}
