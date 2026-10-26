{
  config,
  lib,
  pkgs,
  username,
  dotfilesPath,
  ...
}:

{
  home.activation.exeDevAccess = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -d /exe.dev ] && id exedev >/dev/null 2>&1; then
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
      set -g default-shell "${pkgs.zsh}/bin/zsh"
      set -g default-command "${pkgs.zsh}/bin/zsh -l"
      set -as terminal-overrides ',xterm-256color:RGB,screen-256color:RGB,tmux-256color:RGB'
      set -as terminal-features ',xterm-256color:RGB,tmux-256color:RGB'
    '';
  };
}
