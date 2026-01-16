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
    # ruby  # conflicts with gotools (both have bin/bundle)
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
    bun

    # Formatters
    stylua
    shfmt
    prettierd
    nixfmt
    oxfmt # JS/TS formatter (oxc)

    # LSPs
    lua-language-server
    vscode-langservers-extracted
    typescript-language-server
    tailwindcss-language-server
    dockerfile-language-server
    yaml-language-server
    nil # Nix LSP
    gopls
    # rust-analyzer provided by rustup
    # ty (Python) installed via: uv tool install ty

    # Linters
    oxlint
    golangci-lint

    # Go tools
    gotools # includes goimports
    delve # debugger

    # Debuggers
    # codelldb: run `uv tool install codelldb` or use Mason for now

    # Rust tools
    cargo-expand
    cargo-insta

    # Version control
    git-town # stacked PR workflow for git

    # Claude Code (via claude-code-nix)
    claude-code.default

    # GUI Apps - moved to Homebrew casks for reliability
    # nix-casks can be unreliable, using homebrew.nix instead
  ];
}
