{
  description = "psteinroe's cross-platform system and home configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # devenv CLI, pinned separately so it can track the version project devenv.lock files expect
    # without bumping every other package
    nixpkgs-devenv.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # Pi coding agent (from llm-agents.nix)
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Remote skill sources
    gh-stack-skills = {
      url = "github:github/gh-stack";
      flake = false;
    };

    mattpocock-skills = {
      url = "github:mattpocock/skills";
      flake = false;
    };

    # Claude Code and Codex skills (full-send, babysit-pr, council, ...)
    tstack = {
      url = "github:t3dotgg/tstack";
      flake = false;
    };

    # Rust toolchain (declarative, replaces rustup)
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
          username ? "psteinroe",
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

      # The sd-image-aarch64 module boots Pi 3 and Pi 4 (firmware, U-Boot, device trees).
      mkPi =
        module:
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit username; };
          modules = [
            "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
            module
          ];
        };
    in
    {
      lib = {
        inherit mkHome;
      };

      nixosModules.remote = import ./nix/nixos/remote.nix { inherit inputs; };

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

      homeConfigurations."${username}@linux-aarch64" = mkHome {
        system = "aarch64-linux";
        homeDirectory = "/home/${username}";
        isLinux = true;
      };

      packages.x86_64-linux.home-manager = home-manager.packages.x86_64-linux.home-manager;
      packages.aarch64-linux.home-manager = home-manager.packages.aarch64-linux.home-manager;

      # Raspberry Pi 3 running CLIProxyAPI (cliproxy-psteinroe). Build the SD image on an
      # aarch64-linux machine (.github/workflows/pi-images.yml). Nothing deploys or updates it
      # automatically; updates are occasional and manual (README, CLIProxy).
      nixosConfigurations.cliproxy = mkPi ./nix/nixos/cliproxy;

      packages.aarch64-linux.cliproxy-sd-image =
        self.nixosConfigurations.cliproxy.config.system.build.sdImage;

      # Expose the package set
      darwinPackages = self.darwinConfigurations.${hostname}.pkgs;
    };
}
