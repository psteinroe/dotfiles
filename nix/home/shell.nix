{
  lib,
  pkgs,
  dotfilesPath,
  ...
}:

let
  claudeAccounts = import ./claude-accounts.nix { inherit lib; };
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
      autoload -Uz gh
      autoload -Uz gh-default-branch
      autoload -Uz cpi
      autoload -Uz gpr
      autoload -Uz gclean
      autoload -Uz greset
      autoload -Uz rssh
      autoload -Uz rrebuild
      autoload -Uz rauth
      autoload -Uz claude-login
      autoload -Uz claude-accounts

      # One command per extra Claude Code account, e.g. claude-personal
      ${lib.concatMapStrings (account: ''
        alias claude-${account.name}='CLAUDE_CONFIG_DIR="$HOME/${account.dir}" claude'
      '') claudeAccounts}

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
