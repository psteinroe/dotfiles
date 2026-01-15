# Dotfiles

nix-darwin + home-manager config for macOS.

## Fresh Install

```bash
curl -fsSL https://raw.githubusercontent.com/psteinroe/dotfiles/main/scripts/bootstrap.sh | bash
```

## Manual Install

1. Install Xcode CLI: `xcode-select --install`
2. Install Nix: `curl -sSf -L https://install.determinate.systems/nix | sh`
3. Clone: `git clone https://github.com/psteinroe/dotfiles.git ~/Developer/dotfiles`
4. Build: `nix run nix-darwin -- switch --flake ~/Developer/dotfiles`

## Update

```bash
rebuild
```

## License

MIT
