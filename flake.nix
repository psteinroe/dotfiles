{
  description = "psteinroe's cross-platform system and home configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # GUI apps as nix derivations
    nix-casks = {
      url = "github:atahanyorganci/nix-casks";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Pi coding agent (from llm-agents.nix)
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Tuicr CLI
    tuicr = {
      url = "github:agavra/tuicr";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Herdr terminal workspace manager
    herdr = {
      url = "github:ogulcancelik/herdr";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Herdr/Neovim pane navigation plugin
    vim-herdr-navigation = {
      url = "github:paulbkim-dev/vim-herdr-navigation";
      flake = false;
    };

    # Remote skill sources
    agent-browser-skills = {
      url = "github:vercel-labs/agent-browser";
      flake = false;
    };

    getsentry-skills = {
      url = "github:getsentry/skills";
      flake = false;
    };

    mattpocock-skills = {
      url = "github:mattpocock/skills";
      flake = false;
    };

    # Rust toolchain (declarative, replaces rustup)
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Ghostty config management (binary via Homebrew)
    ghostty-hm-module.url = "github:clo4/ghostty-hm-module";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      nix-homebrew,
      rust-overlay,
      ...
    }:
    let
      username = "psteinroe";
      hostname = "psteinroe";
      darwinSystem = "aarch64-darwin";
      linuxX86System = "x86_64-linux";
      darwinHomeDirectory = "/Users/${username}";
      darwinDotfilesPath = "${darwinHomeDirectory}/Developer/dotfiles";
      darwinSpecialArgs = {
        inherit inputs username;
        system = darwinSystem;
        homeDirectory = darwinHomeDirectory;
        dotfilesPath = darwinDotfilesPath;
        isDarwin = true;
        isLinux = false;
      };

      mkHome =
        {
          system,
          homeDirectory,
          isDarwin ? false,
          isLinux ? false,
        }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ rust-overlay.overlays.default ];
          };
          extraSpecialArgs = {
            inherit
              inputs
              system
              username
              homeDirectory
              isDarwin
              isLinux
              ;
            dotfilesPath = "${homeDirectory}/Developer/dotfiles";
          };
          modules = [ ./nix/home ];
        };
    in
    {
      darwinConfigurations.${hostname} = nix-darwin.lib.darwinSystem {
        system = darwinSystem;
        specialArgs = darwinSpecialArgs;
        modules = [
          ./nix/darwin

          nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              enable = true;
              user = username;
              autoMigrate = true;
              # zsh/path.zsh already includes Homebrew paths; don't inject a
              # per-shell `brew shellenv` call into /etc/zshrc.
              enableZshIntegration = false;
            };
          }

          home-manager.darwinModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "hm-backup";
              extraSpecialArgs = darwinSpecialArgs;
              users.${username} = import ./nix/home;
            };
          }
        ];
      };

      homeConfigurations."${username}@linux-x86_64" = mkHome {
        system = linuxX86System;
        homeDirectory = "/home/${username}";
        isLinux = true;
      };

      # Expose the package set
      darwinPackages = self.darwinConfigurations.${hostname}.pkgs;
    };
}
