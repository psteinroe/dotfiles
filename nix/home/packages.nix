{
  pkgs,
  inputs,
  system,
  ...
}:

let
  claude-code = inputs.claude-code.packages.${system};
  codex-cli = inputs.codex-cli.packages.${system};
  llm-agents = inputs.llm-agents.packages.${system};
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
    postgresql
    just
    hugo
    cmake
    ffmpeg
    imagemagick
    awscli2
    tailscale
    pnpm
    bun
    nodePackages.vercel

    # Formatters
    stylua
    shfmt
    prettierd
    nixfmt
    oxfmt # JS/TS formatter (oxc)

    # LSPs
    lua-language-server
    vscode-langservers-extracted
    typescript-go # tsgo - native TS language server
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
    luaPackages.luacheck

    # Go tools
    gotools # includes goimports
    delve # debugger

    # Debuggers
    # codelldb: run `uv tool install codelldb` or use Mason for now

    # Rust tools
    cargo-expand
    cargo-insta
    llvmPackages.lld # fast linker for Rust

    # Version control
    git-town # stacked PR workflow for git

    # AI coding assistants
    claude-code.default # pre-built binary via sadjow/claude-code-nix
    codex-cli.default   # pre-built binary via sadjow/codex-cli-nix
    opencode            # from nixpkgs
    llm-agents.pi       # from numtide/llm-agents.nix

    # GUI Apps - moved to Homebrew casks for reliability
    # nix-casks can be unreliable, using homebrew.nix instead
  ];
}
