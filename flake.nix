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

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.disko.follows = "disko";
    };

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # Pi coding agent (from llm-agents.nix)
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Herdr/Neovim pane navigation plugin
    vim-herdr-navigation = {
      url = "github:paulbkim-dev/vim-herdr-navigation";
      flake = false;
    };

    # Remote skill sources
    getsentry-skills = {
      url = "github:getsentry/skills";
      flake = false;
    };

    gh-stack-skills = {
      url = "github:github/gh-stack";
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
      hetznerT3codeTransport = "tailscale-serve";
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
          t3codeTransport ? "tailscale-serve",
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
              t3codeTransport
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
        # Generic/standalone Linux includes exe.dev, whose Tailscale Serve path
        # currently drops large post-quantum TLS handshakes. Bind directly to
        # its tailnet address instead; traffic remains private to Tailscale.
        t3codeTransport = "tailscale-direct";
      };

      nixosConfigurations.hetzner-dev = nixpkgs.lib.nixosSystem {
        system = linuxX86System;
        specialArgs = {
          inherit inputs self username;
          t3codeTransport = hetznerT3codeTransport;
          system = linuxX86System;
          homeDirectory = "/home/${username}";
          dotfilesPath = self;
          isDarwin = false;
          isLinux = true;
        };
        modules = [
          inputs.disko.nixosModules.disko
          ./nix/nixos/hosts/hetzner-dev
          home-manager.nixosModules.home-manager
          {
            nixpkgs.overlays = [ rust-overlay.overlays.default ];
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "hm-backup";
              extraSpecialArgs = {
                inherit inputs username;
                system = linuxX86System;
                homeDirectory = "/home/${username}";
                dotfilesPath = self;
                isDarwin = false;
                isLinux = true;
                t3codeTransport = hetznerT3codeTransport;
              };
              users.${username} = import ./nix/home;
            };
          }
        ];
      };

      apps = nixpkgs.lib.genAttrs [ darwinSystem linuxX86System ] (system: {
        nixos-anywhere = {
          type = "app";
          program = "${inputs.nixos-anywhere.packages.${system}.default}/bin/nixos-anywhere";
        };
      });

      # Expose the package set
      darwinPackages = self.darwinConfigurations.${hostname}.pkgs;
    };
}
