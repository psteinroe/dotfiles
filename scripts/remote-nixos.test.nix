# Evaluation only: nix eval --impure --json --file scripts/remote-nixos.test.nix
let
  flake = builtins.getFlake "git+file://${toString ../.}";
  lib = flake.inputs.nixpkgs.lib;
  check =
    system:
    let
      evaluated = lib.nixosSystem {
        inherit system;
        modules = [
          flake.nixosModules.remote
          {
            dotfiles.remote.user = "fixture";
            dotfiles.remote.home = "/home/fixture";
            networking.hostName = "fixture";
            users.users.fixture.isNormalUser = true;
            fileSystems."/" = {
              device = "/dev/fixture";
              fsType = "ext4";
            };
            boot.loader.grub.devices = [ "nodev" ];
            system.stateVersion = "24.11";
          }
        ];
      };
      config = evaluated.config;
      # T3 owns its service unit; dotfiles only ships this drop-in.
      dropIn =
        config.home-manager.users.fixture.xdg.configFile."systemd/user/t3code.service.d/dotfiles.conf".text;
    in
    assert config.users.users.fixture.linger;
    assert config.services.tailscale.enable;
    assert config.programs.nix-ld.enable;
    assert lib.hasInfix ''Environment="NIX_LD=/run/current-system/sw/share/nix-ld/lib/ld.so"'' dropIn;
    assert lib.hasInfix "EnvironmentFile=-%h/.config/dotfiles/t3code.env" dropIn;
    assert !(config.home-manager.users.fixture.systemd.user.services ? t3code);
    assert config.networking.firewall.interfaces.tailscale0.allowedTCPPorts == [ 3773 ];
    assert config.home-manager.users.fixture.home.homeDirectory == "/home/fixture";
    assert config.home-manager.users.fixture.home.username == "fixture";
    {
      toplevel = config.system.build.toplevel.drvPath;
      home = config.home-manager.users.fixture.home.activationPackage.drvPath;
      inherit dropIn;
    };
in
lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] check
