{ pkgs, inputs, system, ... }:

let
  nix-casks = inputs.nix-casks.packages.${system};
  claude-code = inputs.claude-code.packages.${system};
in
{
  home.packages = with pkgs; [
    # Shell utilities
    bat
    eza
    tree
    wget
    curl
    htop

    # Search
    ripgrep
    fd

    # Languages
    nodejs_22
    go
    lua
    elixir
    ruby
    rustup

    # Python
    uv

    # Editor
    neovim

    # Dev tools
    jq
    yq-go
    just
    hugo
    cmake
    ffmpeg
    awscli2
    pnpm

    # Formatters
    stylua
    shfmt
    prettierd
    nixfmt-rfc-style

    # LSPs
    lua-language-server
    vscode-langservers-extracted
    typescript-language-server
    tailwindcss-language-server
    dockerfile-language-server-nodejs
    yaml-language-server
    nil # Nix LSP
    gopls
    rust-analyzer

    # Linters
    eslint_d
    golangci-lint

    # Rust tools
    cargo-expand
    cargo-insta

    # Git tools (managed in git.nix but need packages)
    git-stack

    # Claude Code (via claude-code-nix)
    claude-code.default

    # GUI Apps (via nix-casks)
    nix-casks.slack
    nix-casks.discord
    nix-casks.raycast
    nix-casks.bitwarden
    nix-casks.stats
    nix-casks.timing
    nix-casks.linear-linear
    nix-casks.bruno
    nix-casks.orbstack
    nix-casks.spotify
    nix-casks.google-chrome
    nix-casks.font-fira-code-nerd-font
    nix-casks.tailscale
  ];
}
