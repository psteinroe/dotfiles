{
  pkgs,
  lib,
  inputs,
  system,
  isLinux ? false,
  ...
}:

let
  claudeCode = lib.attrByPath [ system "default" ] null inputs.claude-code.packages;
  codexCli = lib.attrByPath [ system "default" ] null inputs.codex-cli.packages;
  piAgent = lib.attrByPath [ system "pi" ] null inputs.llm-agents.packages;
  tuicr = lib.attrByPath [ system "default" ] null inputs.tuicr.packages;
  optionalPackage = pkg: lib.optional (pkg != null) pkg;
  piWebToolsNodeModules = pkgs.buildNpmPackage {
    pname = "pi-web-tools-extension-deps";
    version = "0.1.0";
    src = ../../agents/pi/extensions/web-tools;
    npmDepsHash = "sha256-U280AVJ/2b2gXgFv1vPAVGXOcynJkJ+vwfAU1NZ4c/Y=";
    dontNpmBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -R node_modules $out/node_modules
      runHook postInstall
    '';
  };
in
{
  home = {
    packages =
      with pkgs;
      [
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
        nodejs_24
        go
        lua
        elixir
        # ruby  # conflicts with gotools (both have bin/bundle)
        (rust-bin.stable.latest.default.override {
          extensions = [
            "rust-src"
            "rust-analyzer"
            "clippy"
          ];
        })

        # Python
        uv

        # Editor
        neovim
        tree-sitter

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
        # rust-analyzer provided by rust-overlay (see rust-bin in Languages)
        # ty (Python) installed via: uv tool install ty

        # Linters
        oxlint
        golangci-lint
        luaPackages.luacheck

        # Go tools
        delve # debugger

        # Debuggers
        # codelldb: run `uv tool install codelldb` or use Mason for now

        # Rust tools
        cargo-expand
        cargo-insta
        llvmPackages.lld # fast linker for Rust

        # Version control
        diffnav # GitHub-like diff pager for git/gh PR diffs

        # AI coding assistants from nixpkgs
        opencode
      ]
      ++ lib.optional isLinux tmux
      ++ optionalPackage tuicr
      ++ optionalPackage claudeCode
      ++ optionalPackage codexCli
      ++ optionalPackage piAgent;

  }
  // lib.optionalAttrs (piAgent != null) {
    # Expose pi-coding-agent's bundled node_modules to user-installed pi
    # extensions in ~/.pi/agent/extensions/, which otherwise cannot resolve
    # imports like `diff` or `@sinclair/typebox`.
    activation.piExtensionDeps = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD mkdir -p $HOME/.pi/agent
      $DRY_RUN_CMD ln -sfn ${piAgent}/lib/node_modules/@earendil-works/pi-coding-agent/node_modules \
        $HOME/.pi/agent/node_modules

      if [ -d "$HOME/.pi/agent/extensions/web-tools" ]; then
        $DRY_RUN_CMD ln -sfn ${piWebToolsNodeModules}/node_modules \
          "$HOME/.pi/agent/extensions/web-tools/node_modules"
      fi
    '';
  };
}
