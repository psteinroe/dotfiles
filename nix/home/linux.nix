{ config, dotfilesPath, ... }:

{
  home.file = {
    ".ssh/config".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/ssh_config.linux";
    ".config/lazygit/config.yml".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/lazygit.yml";
    ".hushlogin".text = "";

    ".tmux.conf".text = ''
      set -g status off
      set -g mouse off
      set -g escape-time 10
      set -g focus-events on
      set -g default-terminal "tmux-256color"
      set -as terminal-overrides ',xterm-256color:RGB,screen-256color:RGB,tmux-256color:RGB'
    '';
  };
}
