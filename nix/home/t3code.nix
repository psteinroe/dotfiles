{
  config,
  lib,
  pkgs,
  homeDirectory,
  ...
}:

let
  # T3 installs and updates itself here (`t3 update`; its apps update the server to their own version).
  t3 = "${homeDirectory}/.local/bin/t3";

  # Agent processes inherit this PATH, so keep the complete managed development
  # environment plus OS-installed provider CLIs such as /usr/local/bin/codex.
  managedUserPath = "${homeDirectory}/.local/bin:/etc/profiles/per-user/${baseNameOf homeDirectory}/bin:${homeDirectory}/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin";

  waitForTailscale = pkgs.writeShellScript "t3code-wait-for-tailscale" ''
    for _ in $(${pkgs.coreutils}/bin/seq 1 30); do
      if ${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null \
        | ${pkgs.gnugrep}/bin/grep -Eq '"BackendState"[[:space:]]*:[[:space:]]*"Running"'; then
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 2
    done

    echo "Tailscale did not become ready within 60 seconds" >&2
    exit 1
  '';

  # T3 projects get their own clones, apart from any <repo>.git worktrees in ~/Developer
  t3Projects = {
    hellomateo = "https://github.com/getmateo/hellomateo.git";
    postgres-conductor = "https://github.com/psteinroe/postgres-conductor.git";
    postgres-language-server = "https://github.com/supabase-community/postgres-language-server.git";
    operations-platform = "https://github.com/getmateo/operations-platform.git";
    fabrial = "https://github.com/psteinroe/fabrial.git";
    postgres-stream = "https://github.com/psteinroe/postgres-stream.git";
    ce-platform = "https://github.com/getmateo/ce-platform.git";
    ninjascale = "https://github.com/psteinroe/ninjascale.git";
  };
  t3ProjectsDir = "${homeDirectory}/Developer/t3";
in
{
  # T3's own service unit stays T3's. This drop-in only adds the agent environment and
  # binds the tailnet address written below; without it T3 stays on 127.0.0.1.
  xdg.configFile."systemd/user/t3code.service.d/dotfiles.conf".text = ''
    [Service]
    ExecStartPre=${waitForTailscale}
    Environment="PATH=${managedUserPath}"
    # Needed on NixOS even without a PAM login; ignored by native glibc on other hosts.
    Environment="NIX_LD=/run/current-system/sw/share/nix-ld/lib/ld.so"
    Environment="NIX_LD_LIBRARY_PATH=/run/current-system/sw/share/nix-ld/lib"
    EnvironmentFile=-%h/.config/dotfiles/t3code.env
  '';

  # Installs T3 and its service only when missing: reinstalling restarts the service and
  # interrupts agents. remote setup records the Mac app's version for the first install.
  home.activation.t3code = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
    if [ -z "''${DRY_RUN:-}" ]; then (
      export PATH="${pkgs.curl}/bin:${pkgs.gnutar}/bin:${pkgs.gzip}/bin:${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:/run/current-system/sw/bin:/usr/bin:/bin:$PATH"
      state="$HOME/.config/dotfiles"
      mkdir -p "$state"

      # Tailnet addresses are stable per node; record this one for the drop-in.
      ip=$(${pkgs.tailscale}/bin/tailscale ip -4 2>/dev/null | head -n 1 || true)
      case "$ip" in
        100.*) (umask 077; printf 'T3CODE_HOST=%s\nT3CODE_PORT=3773\n' "$ip" >"$state/t3code.env") ;;
        *) echo "warning: Tailscale has no address yet; T3 stays on 127.0.0.1 until the next switch" >&2 ;;
      esac

      if [ ! -x "${t3}" ]; then
        version=$(cat "$state/t3-install-version" 2>/dev/null || true)
        installer=$(mktemp)
        if curl -fsSL -o "$installer" https://t3.codes/install.sh &&
          T3CODE_VERSION="$version" sh "$installer"; then
          rm -f "$state/t3-install-version"
        else
          echo "warning: could not install T3 Code" >&2
        fi
        rm -f "$installer"
      fi
      if [ -x "${t3}" ] && [ ! -e "${config.xdg.configHome}/systemd/user/t3code.service" ]; then
        "${t3}" service install || echo "warning: could not install the T3 Code service" >&2
      fi
    ) fi
  '';

  # Clones and registers missing projects only; never re-clones, removes, or touches existing ones
  home.activation.t3codeProjects = lib.hm.dag.entryAfter [ "t3code" ] (
    ''
      add_t3_project() {
        name="$1"
        url="$2"
        path="${t3ProjectsDir}/$name"

        if [ ! -d "$path/.git" ]; then
          $DRY_RUN_CMD mkdir -p "${t3ProjectsDir}"
          # Git's credential helper runs `gh`, which activation's PATH lacks
          if ! PATH="${config.home.profileDirectory}/bin:$PATH" \
            $DRY_RUN_CMD ${pkgs.git}/bin/git clone --quiet --recurse-submodules "$url" "$path"; then
            echo "warning: could not clone $url for T3 Code" >&2
            return 0
          fi
        fi

        if [ -z "''${DRY_RUN:-}" ] && [ -x "${t3}" ] &&
          ! output=$(${t3} project add --title "$name" "$path" 2>&1) &&
          ! grep -q "already exists" <<<"$output"; then
          echo "warning: could not add $path to T3 Code: $output" >&2
        fi
      }

    ''
    + lib.concatStrings (
      lib.mapAttrsToList (name: url: ''
        add_t3_project ${lib.escapeShellArg name} ${lib.escapeShellArg url}
      '') t3Projects
    )
  );
}
