{ config, dotfilesPath, ... }:

{
  xdg.configFile = {
    "ghostty/config".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/ghostty.conf";
    "aerospace/aerospace.toml".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/aerospace.toml";
  };

  home.file = {
    ".ssh/config".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/ssh_config";

    # Lazygit (macOS path)
    "Library/Application Support/lazygit/config.yml".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/lazygit.yml";
  };
}
