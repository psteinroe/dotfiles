{ pkgs, inputs, system, ... }:

let
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

    # GUI Apps - moved to Homebrew casks for reliability
    # nix-casks can be unreliable, using homebrew.nix instead
  ];
}
