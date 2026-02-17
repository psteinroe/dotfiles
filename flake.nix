{
  description = "psteinroe's Darwin system configuration";

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

    # Claude Code CLI (pre-built binary)
    claude-code = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # OpenAI Codex CLI (pre-built binary)
    codex-cli = {
      url = "github:sadjow/codex-cli-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Pi coding agent (from llm-agents.nix)
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Ghostty config management (binary via Homebrew)
    ghostty-hm-module.url = "github:clo4/ghostty-hm-module";
  };

  outputs = inputs@{ self, nixpkgs, nix-darwin, home-manager, nix-homebrew, nix-casks, claude-code, codex-cli, llm-agents, ghostty-hm-module, ... }:
    let
      system = "aarch64-darwin";
      username = "psteinroe";
      hostname = "psteinroe";
    in
    {
      darwinConfigurations.${hostname} = nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = { inherit inputs system username; };
        modules = [
          ./nix/darwin

          nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              enable = true;
              user = username;
              autoMigrate = true;
            };
          }

          home-manager.darwinModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs system username; };
              users.${username} = import ./nix/home;
            };
          }
        ];
      };

      # Expose the package set
      darwinPackages = self.darwinConfigurations.${hostname}.pkgs;
    };
}
