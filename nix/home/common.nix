{
  config,
  lib,
  pkgs,
  inputs,
  username,
  homeDirectory ? null,
  dotfilesPath,
  isDarwin ? false,
  ...
}:

let
  resolvedHomeDirectory =
    if homeDirectory != null then
      homeDirectory
    else if isDarwin then
      "/Users/${username}"
    else
      "/home/${username}";
  herdrPackage = lib.attrByPath [
    pkgs.stdenv.hostPlatform.system
    "default"
  ] null inputs.herdr.packages;
in
{
  home = {
    username = lib.mkForce username;
    homeDirectory = lib.mkForce resolvedHomeDirectory;
    stateVersion = "24.11";

    # Install Python tools via uv (runs only on rebuild, not every shell)
    activation.uvTools = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${pkgs.uv}/bin/uv tool install ty --quiet 2>/dev/null || true
      ${pkgs.uv}/bin/uv tool install ruff --quiet 2>/dev/null || true
    '';

    # Reuse the declarative plugin registry for existing named sessions. Herdr
    # stores plugin registries per session, while config.toml stays global.
    activation.herdrNamedSessionPlugins = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      if [ -f "$HOME/.config/herdr/plugins.json" ] && [ -d "$HOME/.config/herdr/sessions" ]; then
        for session_dir in "$HOME"/.config/herdr/sessions/*; do
          [ -d "$session_dir" ] || continue
          $DRY_RUN_CMD ln -sfn ../../plugins.json "$session_dir/plugins.json"
        done
      fi
    '';

    activation.herdrPluginLinks = lib.mkIf (herdrPackage != null) (
      lib.hm.dag.entryAfter [ "herdrNamedSessionPlugins" ] ''
        if [ -x ${herdrPackage}/bin/herdr ]; then
          ${herdrPackage}/bin/herdr plugin link ${inputs.vim-herdr-navigation} >/dev/null 2>&1 || true
          ${herdrPackage}/bin/herdr plugin link ${dotfilesPath}/herdr/plugins/worktree-sync >/dev/null 2>&1 || true
        fi
      ''
    );

    # Generate shell completions
    activation.completions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p $HOME/.zsh/completions
      ${pkgs.just}/bin/just --completions zsh > $HOME/.zsh/completions/_just 2>/dev/null || true
      ${pkgs.gh}/bin/gh completion -s zsh > $HOME/.zsh/completions/_gh 2>/dev/null || true
      ${pkgs.rustup}/bin/rustup completions zsh > $HOME/.zsh/completions/_rustup 2>/dev/null || true
      ${pkgs.rustup}/bin/rustup completions zsh cargo > $HOME/.zsh/completions/_cargo 2>/dev/null || true
      ${pkgs.bun}/bin/bun completions > $HOME/.zsh/completions/_bun 2>/dev/null || true
      ${pkgs.fd}/bin/fd --gen-completions zsh > $HOME/.zsh/completions/_fd 2>/dev/null || true
      ${pkgs.ripgrep}/bin/rg --generate complete-zsh > $HOME/.zsh/completions/_rg 2>/dev/null || true
    '';
  };

  # Let Home Manager manage itself
  programs.home-manager.enable = true;

  # XDG config files (symlinked for fast iteration)
  xdg.configFile = {
    "nvim".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/nvim";
    "starship.toml".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/starship.toml";
    "atuin/config.toml".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/atuin.toml";
    "tuicr/config.toml".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/tuicr/config.toml";
    "tuicr/themes".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/tuicr/themes";
    "herdr/config.toml".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/herdr/config.toml";

    "herdr/plugins.json" = lib.mkIf (herdrPackage != null) {
      force = true;
      text = builtins.toJSON [
        {
          plugin_id = "vim-herdr-navigation";
          name = "Vim Herdr Navigation";
          version = "0.1.0";
          min_herdr_version = "0.7.0";
          description = "Seamless Ctrl+h/j/k/l navigation across herdr panes and Vim/Neovim splits";
          manifest_path = "${inputs.vim-herdr-navigation}/herdr-plugin.toml";
          plugin_root = "${inputs.vim-herdr-navigation}";
          enabled = true;
          platforms = [
            "linux"
            "macos"
          ];
          actions = [
            {
              id = "down";
              title = "Navigate down (Vim/herdr)";
              contexts = [ "global" ];
              command = [
                "bash"
                "navigate.sh"
                "down"
              ];
            }
            {
              id = "left";
              title = "Navigate left (Vim/herdr)";
              contexts = [ "global" ];
              command = [
                "bash"
                "navigate.sh"
                "left"
              ];
            }
            {
              id = "right";
              title = "Navigate right (Vim/herdr)";
              contexts = [ "global" ];
              command = [
                "bash"
                "navigate.sh"
                "right"
              ];
            }
            {
              id = "up";
              title = "Navigate up (Vim/herdr)";
              contexts = [ "global" ];
              command = [
                "bash"
                "navigate.sh"
                "up"
              ];
            }
          ];
          source = {
            kind = "local";
          };
        }
        {
          plugin_id = "psteinroe.worktree-sync";
          name = "Psteinroe Worktree Sync";
          version = "0.1.0";
          min_herdr_version = "0.7.0";
          description = "Make Herdr workspaces follow psteinroe dotfiles Git worktrees.";
          manifest_path = "${dotfilesPath}/herdr/plugins/worktree-sync/herdr-plugin.toml";
          plugin_root = "${dotfilesPath}/herdr/plugins/worktree-sync";
          enabled = true;
          platforms = [
            "linux"
            "macos"
          ];
          actions = [
            {
              id = "sync";
              title = "Sync Git worktrees into Herdr";
              contexts = [ "workspace" ];
              command = [
                "zsh"
                "sync.sh"
              ];
            }
            {
              id = "open";
              title = "Open existing worktree";
              contexts = [ "workspace" ];
              command = [
                "zsh"
                "open.sh"
              ];
            }
            {
              id = "create";
              title = "Create worktree";
              contexts = [ "workspace" ];
              command = [
                "zsh"
                "create.sh"
              ];
            }
            {
              id = "hide";
              title = "Hide current worktree workspace";
              contexts = [ "workspace" ];
              command = [
                "zsh"
                "hide.sh"
              ];
            }
            {
              id = "manager";
              title = "Open worktree manager";
              contexts = [ "workspace" ];
              command = [
                "zsh"
                "manager-action.sh"
              ];
            }
            {
              id = "bootstrap";
              title = "Bootstrap panes for this workspace";
              contexts = [ "workspace" ];
              command = [
                "zsh"
                "bootstrap.sh"
              ];
            }
            {
              id = "clean";
              title = "Clean merged/closed worktrees";
              contexts = [ "workspace" ];
              command = [
                "zsh"
                "clean.sh"
              ];
            }
          ];
          panes = [
            {
              id = "manager";
              title = "Worktree Manager";
              placement = "overlay";
              command = [
                "zsh"
                "manager.sh"
              ];
            }
          ];
          events = [
            {
              on = "worktree.created";
              command = [
                "zsh"
                "on-worktree.sh"
              ];
            }
            {
              on = "worktree.opened";
              command = [
                "zsh"
                "on-worktree.sh"
              ];
            }
          ];
          source = {
            kind = "local";
          };
        }
      ];
    };
  };

  # Home directory files (symlinked for fast iteration)
  home.file = {
    ".gitconfig".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/gitconfig";
    ".ripgreprc".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/ripgrep";

    # Redirect npm global installs to a user-writable prefix.
    # nix-packaged node has a read-only store prefix, so `npm install -g`
    # (used by e.g. pi extension installs) fails with EACCES otherwise.
    ".npmrc".text = ''
      prefix=''${HOME}/.npm-global
    '';
    # zshrc is managed by home-manager (shell.nix) - sources zsh/*.zsh files
  };
}
