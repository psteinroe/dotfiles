# Keeps the cliproxy Pi on main: .github/workflows/cliproxy-deploy.yml builds and signs
# this system on an aarch64 runner and publishes it as the cliproxy-pi release
# (scripts/cliproxy-publish.sh). Hourly, the Pi downloads what that release names and
# switches to it, so it neither evaluates nor builds, and CI needs no way in. A switch
# that leaves CLIProxyAPI unhealthy is rolled back and that system is not tried again.
{
  config,
  pkgs,
  ...
}:

let
  release = "https://github.com/psteinroe/dotfiles/releases/download/cliproxy-pi";
  # Public half of the CLIPROXY_SIGNING_KEY Actions secret
  publicKey = "cliproxy-ci-1:l4nzBSy7/BK9dnHeszk+KMDfCPZsduakRn+qTShTOgg=";
  stateDir = "/var/lib/cliproxy-deploy";
  profile = "/nix/var/nix/profiles/system";
in
{
  systemd.services.cliproxy-deploy = {
    description = "Switch to the cliproxy Pi system published by CI";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    # Switching must not stop or restart the unit that runs the switch
    restartIfChanged = false;
    unitConfig.X-StopOnRemoval = false;
    path = [
      config.nix.package
      pkgs.coreutils
      pkgs.curl
      pkgs.gnutar
      pkgs.systemd
    ];
    script = ''
      set -euo pipefail
      cd ${stateDir}

      want=$(curl -fsSL --retry 3 ${release}/system)
      case "$want" in
        /nix/store/*-nixos-system-*) ;;
        *)
          echo "Unexpected system path: $want"
          exit 1
          ;;
      esac
      current=$(readlink -f /run/current-system)
      if [ "$want" = "$current" ]; then
        echo "Already on $want"
        exit 0
      fi
      if [ "$want" = "$(cat failed 2>/dev/null || true)" ]; then
        echo "Not retrying $want, it failed before"
        exit 0
      fi

      echo "Fetching $want"
      h=''${want#/nix/store/}
      rm -rf cache
      mkdir cache
      curl -fsSL --retry 3 ${release}/cache-''${h%%-*}.tar | tar -xf - -C cache
      # Everything else comes from cache.nixos.org; paths from CI must carry its signature
      nix-store --realise "$want" \
        --option extra-substituters "file://${stateDir}/cache" \
        --option extra-trusted-public-keys "${publicKey}"
      rm -rf cache

      # The API key stays out of curl's arguments (printf is a builtin)
      healthy() {
        for _ in $(seq 30); do
          if curl -fsS -o /dev/null -H @<(printf 'Authorization: Bearer %s\n' "$(</var/lib/cliproxyapi/access-key)") \
            http://127.0.0.1:8317/v1/models; then
            return 0
          fi
          sleep 2
        done
        return 1
      }

      nix-env --profile ${profile} --set "$want"
      if "$want/bin/switch-to-configuration" switch && healthy; then
        rm -f failed
        echo "Switched to $want"
        exit 0
      fi

      echo "$want is unhealthy, rolling back to $current"
      echo "$want" >failed
      nix-env --profile ${profile} --set "$current"
      "$current/bin/switch-to-configuration" switch || true
      exit 1
    '';
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "cliproxy-deploy";
      StateDirectoryMode = "0700";
    };
  };

  systemd.timers.cliproxy-deploy = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      RandomizedDelaySec = "10m";
      Persistent = true;
    };
  };
}
