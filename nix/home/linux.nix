{
  config,
  lib,
  pkgs,
  username,
  homeDirectory,
  dotfilesPath,
  ...
}:

let
  moshiHookVersion = "0.2.68";
  moshiHook = pkgs.stdenvNoCC.mkDerivation {
    pname = "moshi-hook";
    version = moshiHookVersion;
    src = pkgs.fetchurl {
      url = "https://cdn.getmoshi.app/hook/v${moshiHookVersion}/moshi-hook_Linux_x86_64.tar.gz";
      hash = "sha256-48ktUuio7rEHyoqPkxSsjcQyL6RTSMzmGIG55SFyyXw=";
    };
    dontUnpack = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin"
      ${pkgs.gnutar}/bin/tar -xzf "$src" -C "$out/bin" moshi-hook
      chmod 0755 "$out/bin/moshi-hook"
      ln -s moshi-hook "$out/bin/moshi"
      runHook postInstall
    '';
  };

  managedUserPath = "${homeDirectory}/.local/bin:${homeDirectory}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin";

  # exe.dev's public SSH gateway always enters the stock image as `exedev`,
  # while the managed development environment and Herdr sessions belong to
  # `psteinroe`. Moshi discovers and invokes integrations as the SSH login
  # user, so expose small global bridges that run them as the managed user.
  exeDevHerdrBridge = pkgs.writeShellScript "herdr-exedev-bridge" ''
    set -euo pipefail

    target_user="''${HERDR_BRIDGE_USER:-${username}}"
    target_home="''${HERDR_BRIDGE_HOME:-${homeDirectory}}"
    target_path="''${HERDR_BRIDGE_PATH:-${managedUserPath}}"
    target_shell="''${HERDR_BRIDGE_SHELL:-$target_home/.nix-profile/bin/zsh}"
    target_runtime_dir="/run/user/$(id -u "$target_user")"

    exec /usr/bin/sudo -n -u "$target_user" /usr/bin/env \
      HOME="$target_home" \
      USER="$target_user" \
      LOGNAME="$target_user" \
      PATH="$target_path" \
      SHELL="$target_shell" \
      XDG_RUNTIME_DIR="$target_runtime_dir" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=$target_runtime_dir/bus" \
      TERM="''${TERM:-xterm-256color}" \
      COLORTERM="''${COLORTERM:-truecolor}" \
      MOSHI_CLIENT="''${MOSHI_CLIENT:-}" \
      /bin/sh -c 'cd "$HOME" || exit 1; exec herdr "$@"' herdr "$@"
  '';

  exeDevMoshiHookBridge = pkgs.writeShellScript "moshi-hook-exedev-bridge" ''
    set -euo pipefail

    target_user="''${MOSHI_HOOK_BRIDGE_USER:-${username}}"
    target_home="''${MOSHI_HOOK_BRIDGE_HOME:-${homeDirectory}}"
    target_runtime_dir="/run/user/$(id -u "$target_user")"

    exec /usr/bin/sudo -n -u "$target_user" /usr/bin/env \
      HOME="$target_home" \
      USER="$target_user" \
      LOGNAME="$target_user" \
      PATH="${managedUserPath}" \
      XDG_RUNTIME_DIR="$target_runtime_dir" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=$target_runtime_dir/bus" \
      /bin/sh -c 'cd "$HOME" || exit 1; exec "$0" "$@"' \
      ${moshiHook}/bin/moshi-hook "$@"
  '';
in
{
  home.packages = [
    pkgs.mosh
    moshiHook
  ];

  home.activation.exeDevMobileAccess = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -d /exe.dev ] && id exedev >/dev/null 2>&1; then
      $DRY_RUN_CMD /usr/bin/sudo -n ${pkgs.coreutils}/bin/install \
        -o root -g root -m 0755 \
        ${exeDevHerdrBridge} /usr/local/bin/herdr
      $DRY_RUN_CMD /usr/bin/sudo -n ${pkgs.coreutils}/bin/install \
        -o root -g root -m 0755 \
        ${exeDevMoshiHookBridge} /usr/local/bin/moshi-hook
      $DRY_RUN_CMD /usr/bin/sudo -n ${pkgs.coreutils}/bin/install \
        -o exedev -g exedev -m 0755 -d /home/exedev/.local/bin
      $DRY_RUN_CMD /usr/bin/sudo -n ${pkgs.coreutils}/bin/install \
        -o root -g root -m 0755 \
        ${exeDevMoshiHookBridge} /home/exedev/.local/bin/moshi-hook
      $DRY_RUN_CMD /usr/bin/sudo -n ${pkgs.coreutils}/bin/ln \
        -sfn /home/exedev/.local/bin/moshi-hook /home/exedev/.local/bin/moshi
      $DRY_RUN_CMD /usr/bin/sudo -n ${pkgs.coreutils}/bin/ln \
        -sfn ${moshiHook}/bin/moshi-hook /usr/local/bin/moshi
      $DRY_RUN_CMD /usr/bin/sudo -n ${pkgs.coreutils}/bin/ln \
        -sfn ${pkgs.mosh}/bin/mosh-server /usr/local/bin/mosh-server
      $DRY_RUN_CMD /usr/bin/sudo -n /usr/bin/loginctl enable-linger ${username}

      sshd_config=/exe.dev/etc/ssh/sshd_config
      authorized_keys_line='AuthorizedKeysFile /exe.dev/etc/ssh/authorized_keys .ssh/authorized_keys'
      current_line=$(/usr/bin/sudo -n ${pkgs.gnugrep}/bin/grep -m1 '^AuthorizedKeysFile ' "$sshd_config" || true)

      if [ "$current_line" != "$authorized_keys_line" ]; then
        if [ -n "$DRY_RUN_CMD" ]; then
          echo "Would allow per-user authorized_keys in $sshd_config"
        else
          tmp_config=$(${pkgs.coreutils}/bin/mktemp)
          trap '${pkgs.coreutils}/bin/rm -f "$tmp_config"' EXIT
          /usr/bin/sudo -n ${pkgs.coreutils}/bin/cat "$sshd_config" \
            | ${pkgs.gnused}/bin/sed "s|^AuthorizedKeysFile .*|$authorized_keys_line|" \
            > "$tmp_config"

          if ! ${pkgs.gnugrep}/bin/grep -qF "$authorized_keys_line" "$tmp_config"; then
            printf '\n%s\n' "$authorized_keys_line" >> "$tmp_config"
          fi

          /usr/bin/sudo -n /exe.dev/bin/sshd -t -f "$tmp_config"
          /usr/bin/sudo -n ${pkgs.coreutils}/bin/install \
            -o root -g root -m 0600 "$tmp_config" "$sshd_config"
          ${pkgs.coreutils}/bin/rm -f "$tmp_config"
          trap - EXIT

          listener_pid=$(
            ${pkgs.procps}/bin/ps -eo pid=,ppid=,args= \
              | ${pkgs.gawk}/bin/awk '$2 == 1 && /\/exe.dev\/bin\/sshd -D/ { print $1; exit }'
          )
          if [ -n "$listener_pid" ]; then
            /usr/bin/sudo -n ${pkgs.coreutils}/bin/kill -HUP "$listener_pid"
          fi
        fi
      fi
    fi
  '';

  # Herdr is managed by Nix. Its self-updater installs to ~/.local/bin, which
  # can leave an older client ahead of the Nix package on PATH and make both
  # Moshi and the local thin-client workflow protocol-incompatible.
  home.activation.removeLegacyHerdrInstall = lib.hm.dag.entryAfter [ "installPackages" ] ''
    if [ -x "${config.home.profileDirectory}/bin/herdr" ] && [ -e "$HOME/.local/bin/herdr" ]; then
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -f "$HOME/.local/bin/herdr"
    fi
  '';

  home.activation.moshiHookAgentIntegrations =
    lib.hm.dag.entryAfter
      [
        "agentConfigs"
        "installPackages"
        "removeLegacyHerdrInstall"
      ]
      ''
        $DRY_RUN_CMD ${moshiHook}/bin/moshi-hook install >/dev/null
      '';

  systemd.user.services.moshi-hook = {
    Unit = {
      Description = "Moshi agent hook daemon";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      ExecStart = "${moshiHook}/bin/moshi-hook serve";
      Restart = "always";
      RestartSec = 5;
      WorkingDirectory = homeDirectory;
      Environment = [
        "HOME=${homeDirectory}"
        "PATH=${managedUserPath}"
      ];
    };
    Install.WantedBy = [ "default.target" ];
  };

  home.file = {
    ".ssh/config".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/ssh_config.linux";
    ".config/lazygit/config.yml".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfilesPath}/lazygit.yml";
    ".hushlogin".text = "";

    ".tmux.conf".text = ''
      set -g status off
      set -g mouse on
      set -g history-limit 50000
      set -g escape-time 10
      set -g focus-events on
      set-environment -g COLORTERM truecolor
      set -g extended-keys on
      set -g extended-keys-format csi-u
      set -g default-terminal "tmux-256color"
      set -g default-shell "/home/psteinroe/.nix-profile/bin/zsh"
      set -g default-command "/home/psteinroe/.nix-profile/bin/zsh -l"
      set -as terminal-overrides ',xterm-256color:RGB,screen-256color:RGB,tmux-256color:RGB'
      set -as terminal-features ',xterm-256color:RGB,tmux-256color:RGB'
    '';
  };
}
