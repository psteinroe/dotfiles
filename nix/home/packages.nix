{
  pkgs,
  lib,
  inputs,
  system,
  isLinux ? false,
  ...
}:

let
  piAgent = lib.attrByPath [ system "pi" ] null inputs.llm-agents.packages;
  tuicr = lib.attrByPath [ system "tuicr" ] null inputs.llm-agents.packages;
  herdr = lib.attrByPath [ system "herdr" ] null inputs.llm-agents.packages;
  optionalPackage = pkg: lib.optional (pkg != null) pkg;

  # Keep pnpm's shebang pointed at the same runtime as the global Node install.
  globalNode = pkgs.nodejs_24;
  globalPnpm = pkgs.pnpm.override { nodejs-slim = pkgs.nodejs-slim_24; };

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

  piExtensionNodeModules = pkgs.buildNpmPackage {
    pname = "pi-extension-runtime-deps";
    version = "0.1.0";
    src = ./pi-extension-deps;
    npmDepsHash = "sha256-IgvmnSdvwQj6zFT7tgfloNvKGN+VFkIxZYGICAnUnu0=";
    npmDepsFetcherVersion = 2;
    npmFlags = [ "--ignore-scripts" ];
    makeCacheWritable = true;
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
        globalNode
        go
        lua
        beamPackages.elixir
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
        google-cloud-sdk
        tailscale
        globalPnpm
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

      ]
      ++ lib.optional isLinux tmux
      ++ optionalPackage tuicr
      ++ optionalPackage herdr
      ++ optionalPackage piAgent;

  }
  // lib.optionalAttrs (piAgent != null) {
    # Install third-party dependencies for local extensions. Pi's built-in
    # extension imports are resolved by Pi itself.
    activation.piExtensionDeps = lib.hm.dag.entryAfter [ "agentConfigs" ] ''
      $DRY_RUN_CMD mkdir -p $HOME/.pi/agent/extensions
      if [ -L "$HOME/.pi/agent/node_modules" ]; then
        $DRY_RUN_CMD rm "$HOME/.pi/agent/node_modules"
      fi

      if [ -d "$HOME/.pi/agent/extensions/web-tools" ]; then
        $DRY_RUN_CMD ln -sfn ${piWebToolsNodeModules}/node_modules \
          "$HOME/.pi/agent/extensions/web-tools/node_modules"
      fi

      for extension in ask-user background-terminals workflows; do
        if [ -d "$HOME/.pi/agent/extensions/$extension" ]; then
          $DRY_RUN_CMD ln -sfn ${piExtensionNodeModules}/node_modules \
            "$HOME/.pi/agent/extensions/$extension/node_modules"
        fi
      done
    '';
  };
}
