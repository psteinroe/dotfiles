# Add to an existing NixOS configuration. Hardware, boot and SSH access stay host-owned.
{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  remote = config.dotfiles.remote;
in
{
  imports = [ inputs.home-manager.nixosModules.home-manager ];

  options.dotfiles.remote = {
    user = lib.mkOption {
      type = lib.types.str;
      description = "Existing development user.";
    };
    home = lib.mkOption {
      type = lib.types.str;
      default = "/home/${remote.user}";
      description = "Development user's home.";
    };
  };

  config = {
    nixpkgs.overlays = [ inputs.rust-overlay.overlays.default ];
    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      extra-substituters = [ "https://cache.numtide.com" ];
      extra-trusted-public-keys = [ "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" ];
    };
    programs.zsh.enable = true;
    # Upstream T3 is a Bun ELF with an FHS interpreter. Patchelf would corrupt
    # its embedded payload, so use nix-ld without changing the executable.
    programs.nix-ld.enable = true;
    users.users.${remote.user} = {
      linger = true;
    };
    services.tailscale.enable = lib.mkDefault true;
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 3773 ];

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "hm-backup";
      extraSpecialArgs = {
        inherit inputs;
        system = pkgs.stdenv.hostPlatform.system;
        username = remote.user;
        homeDirectory = remote.home;
        dotfilesPath = "${remote.home}/Developer/dotfiles";
        isDarwin = false;
        isLinux = true;
      };
      users.${remote.user} = import ../home;
    };
  };
}
