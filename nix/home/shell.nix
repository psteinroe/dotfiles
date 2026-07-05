{ pkgs, dotfilesPath, ... }:

let
  starshipZshInit = pkgs.runCommand "starship-init.zsh" { } ''
    ${pkgs.starship}/bin/starship init zsh > $out
  '';
  atuinZshInit = pkgs.runCommand "atuin-init.zsh" { } ''
    HOME=$TMPDIR ${pkgs.atuin}/bin/atuin init zsh > $out
  '';
  zoxideZshInit = pkgs.runCommand "zoxide-init.zsh" { } ''
    ${pkgs.zoxide}/bin/zoxide init zsh > $out
  '';
  fzfZshInit = pkgs.runCommand "fzf-init.zsh" { } ''
    ${pkgs.fzf}/bin/fzf --zsh > $out
  '';
in
{
  programs.zsh = {
    enable = true;
    enableCompletion = false;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    initContent = ''
      # Source modular zsh config
      ZSH_DIR="${dotfilesPath}/zsh"
      source "$ZSH_DIR/completions.zsh"

      # Cache completion metadata. `compinit -D` re-scans every completion file
      # on every shell startup, which dominates new-tab latency.
      ZSH_COMPDUMP="''${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump-$ZSH_VERSION"
      mkdir -p "''${ZSH_COMPDUMP:h}"
      autoload -U compinit
      if [[ -r "$ZSH_COMPDUMP" ]]; then
        compinit -C -d "$ZSH_COMPDUMP"
      else
        compinit -d "$ZSH_COMPDUMP"
      fi

      source "$ZSH_DIR/env.zsh"
      source "$ZSH_DIR/path.zsh"
      source ${zoxideZshInit}
      if [[ $options[zle] = on ]]; then
        source ${fzfZshInit} 2>/dev/null
      fi
      source "$ZSH_DIR/options.zsh"
      source "$ZSH_DIR/keybindings.zsh"
      source "$ZSH_DIR/aliases.zsh"

      # Autoload custom functions
      fpath=(${dotfilesPath}/zsh/functions $fpath)
      autoload -Uz keychain-environment-variable
      autoload -Uz set-keychain-environment-variable
      autoload -Uz video_to_gif
      autoload -Uz rebuild
      autoload -Uz devhelp
      autoload -Uz coffee
      autoload -Uz wtclone
      autoload -Uz wtfork
      autoload -Uz wtcreate
      autoload -Uz wtcheckout
      autoload -Uz wtlist
      autoload -Uz wtclean
      autoload -Uz wtforceclean
      autoload -Uz wtsetup
      autoload -Uz wtensure
      autoload -Uz hdev
      autoload -Uz hprepare
      autoload -Uz hsyncworktrees
      autoload -Uz hwtcreate
      autoload -Uz gh
      autoload -Uz gh-default-branch
      autoload -Uz cpi
      autoload -Uz gpr
      autoload -Uz gclean
      autoload -Uz greset
      autoload -Uz rdev
      autoload -Uz rherdr
      autoload -Uz rhsyncworktrees
      autoload -Uz rhwtcreate
      autoload -Uz rwtclean
      autoload -Uz rwtforceclean
      autoload -Uz rpushdev
      autoload -Uz rssh
      autoload -Uz rrebuild
      autoload -Uz ragentauth
      autoload -Uz rmcpauth
      autoload -Uz rghauth

      if [[ $TERM != "dumb" ]]; then
        source ${starshipZshInit}
      fi

      if [[ $options[zle] = on ]]; then
        source ${atuinZshInit}
      fi
    '';
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = false;
  };

  programs.atuin = {
    enable = true;
    enableZshIntegration = false;
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = false;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = false;
  };

  programs.direnv = {
    enable = false;
  };
}
