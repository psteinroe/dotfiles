{ config, dotfilesPath, ... }:

{
  home.file = {
    ".ssh/config".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/ssh_config.linux";
    ".config/lazygit/config.yml".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/lazygit.yml";
    ".hushlogin".text = "";

    ".tmux.conf".text = ''
      set -g status off
      set -g mouse on
      set -g history-limit 50000
      set -g escape-time 10
      set -g focus-events on
      set-environment -g COLORTERM truecolor
      set -g extended-keys on
      set -g extended-keys-format csi-u
      set -g default-terminal "tmux-256color"
      set -g default-shell "/home/psteinroe/.nix-profile/bin/zsh"
      set -g default-command "/home/psteinroe/.nix-profile/bin/zsh -l"
      set -as terminal-overrides ',xterm-256color:RGB,screen-256color:RGB,tmux-256color:RGB'
      set -as terminal-features ',xterm-256color:RGB,tmux-256color:RGB'
    '';
  };
}
