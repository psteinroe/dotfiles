{
  config,
  lib,
  pkgs,
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

    # Generate shell completions
    activation.completions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p $HOME/.zsh/completions
      ${pkgs.git-town}/bin/git-town completions zsh > $HOME/.zsh/completions/_git-town 2>/dev/null || true
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
