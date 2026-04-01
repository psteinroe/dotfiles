{ pkgs, ... }:

{
  # Just install the packages - configs are symlinked from dotfiles
  # gitconfig already has delta config, lazygit.yml is symlinked
  programs.git = {
    enable = true;
    # Signing is configured in the symlinked ~/.gitconfig (SSH signing),
    # so opt out of Home Manager's legacy default to silence the warning.
    signing.format = null;
  };
  programs.delta.enable = true;  # No enableGitIntegration - gitconfig has it
  programs.gh = {
    enable = true;
    extensions = [ pkgs.gh-poi ];
  };
  programs.lazygit.enable = true;
}
