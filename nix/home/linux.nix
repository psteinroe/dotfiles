{ config, dotfilesPath, ... }:

{
  home.file = {
    ".ssh/config".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/ssh_config.linux";
    ".config/lazygit/config.yml".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/lazygit.yml";
    ".hushlogin".text = "";
  };
}
