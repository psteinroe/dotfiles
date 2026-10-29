# Joins the tailnet on first boot without SSH: after flashing, save a one-off auth key
# as `tailscale-authkey` on the SD card's FAT partition (FIRMWARE, /boot/firmware on
# the Pi). On boot, if the node isn't logged in yet, this runs `tailscale up` with it
# and deletes the file. With no file, or once logged in, it does nothing.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.pi;
  # sd-image.nix declares this mount as noauto, so the unit mounts it itself
  firmware = "/boot/firmware";
  # Text editors on macOS and Windows like to append .txt
  keyNames = [
    "tailscale-authkey"
    "tailscale-authkey.txt"
  ];
in
{
  options.my.pi.tailscaleUpFlags = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "--advertise-tags=tag:server" ];
    description = "Extra flags for the first-boot `tailscale up`, next to --auth-key and --hostname.";
  };

  config.systemd.services.tailscale-join = {
    description = "Join the tailnet with an auth key from the firmware partition";
    wantedBy = [ "multi-user.target" ];
    after = [
      "tailscaled.service"
      "network-online.target"
    ];
    wants = [
      "tailscaled.service"
      "network-online.target"
    ];
    # `tailscale up` refuses to run when `tailscale set` already changed settings
    before = [ "tailscaled-set.service" ];
    # A transient failure keeps the key and retries a few times, then waits for the
    # next boot
    startLimitIntervalSec = 600;
    startLimitBurst = 5;
    path = [
      config.services.tailscale.package
      pkgs.jq
      pkgs.util-linux
    ];
    script = ''
      set -uo pipefail
      fw=${firmware}

      mounted=
      cleanup() {
        if [ -n "$mounted" ]; then
          sync
          umount "$fw" || echo "Could not unmount $fw"
        fi
      }
      trap cleanup EXIT

      if ! mountpoint -q "$fw"; then
        mkdir -p "$fw"
        # umask: root-only while mounted
        if ! mount -o rw,umask=0077 "$fw"; then
          echo "No firmware partition at $fw, nothing to do"
          exit 0
        fi
        mounted=1
      fi

      key=
      for name in ${lib.escapeShellArgs keyNames}; do
        if [ -s "$fw/$name" ]; then
          key="$fw/$name"
          break
        fi
      done
      if [ -z "$key" ]; then
        echo "No auth key in $fw, nothing to do"
        exit 0
      fi

      # Overwriting can't be guaranteed on FAT on flash, but the key is single-use
      forget() {
        shred -u "$key" 2>/dev/null || rm -f "$key"
        # AppleDouble file macOS writes next to it on FAT
        rm -f "$fw/._''${key##*/}"
        sync
        echo "Deleted $key"
      }

      # NoState and Starting are transient while tailscaled comes up
      state=
      for _ in $(seq 60); do
        state="$(tailscale status --json --peers=false 2>/dev/null | jq -r '.BackendState' || true)"
        case "$state" in
          NeedsLogin | NeedsMachineAuth | Stopped | Running) break ;;
        esac
        sleep 1
      done

      case "$state" in
        NeedsLogin)
          echo "Joining the tailnet as ${config.networking.hostName} with the key from $key"
          # file: keeps the key out of the process list; --timeout keeps a node that
          # waits for device approval from blocking boot
          if ! tailscale up --auth-key="file:$key" ${
            lib.escapeShellArgs (
              [
                "--hostname=${config.networking.hostName}"
                "--timeout=2m"
              ]
              ++ cfg.tailscaleUpFlags
            )
          }; then
            echo "tailscale up failed, keeping $key for the next attempt"
            exit 1
          fi
          echo "Joined the tailnet"
          forget
          ;;
        NeedsMachineAuth | Stopped | Running)
          echo "Already logged in to Tailscale (state $state), the key is not needed"
          forget
          ;;
        *)
          echo "tailscaled did not settle (state ''${state:-unknown}), keeping $key for the next attempt"
          exit 1
          ;;
      esac
    '';
    serviceConfig = {
      Type = "oneshot";
      Restart = "on-failure";
      RestartSec = "30s";
      UMask = "0077";
    };
  };
}
