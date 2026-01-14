{ pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    plugins = [
      {
        name = "zsh-vi-mode";
        src = pkgs.zsh-vi-mode;
        file = "share/zsh-vi-mode/zsh-vi-mode.plugin.zsh";
      }
    ];

    initExtra = ''
      # Autoload custom functions
      fpath=($HOME/Developer/dotfiles/zsh/functions $fpath)
      autoload -Uz keychain-environment-variable
      autoload -Uz set-keychain-environment-variable
      autoload -Uz video_to_gif
      autoload -Uz wtlist
      autoload -Uz wtclean
      autoload -Uz wtcreate
      autoload -Uz ccode
      autoload -Uz ccodex
    '';
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };
}
