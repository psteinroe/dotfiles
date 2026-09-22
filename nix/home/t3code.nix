{
  pkgs,
  homeDirectory,
  t3codeTransport ? "tailscale-serve",
  ...
}:

let
  t3codeVersion = "0.0.42";
  t3code = pkgs.stdenvNoCC.mkDerivation {
    pname = "t3code";
    version = t3codeVersion;

    src = pkgs.fetchurl {
      url = "https://github.com/pingdotgg/t3code/releases/download/v${t3codeVersion}/t3-${t3codeVersion}-linux-x64.tar.gz";
      hash = "sha256-9QTpMe5EBr/nZ1QUfLDioPMA11xsUFoOF0oeefZc7qM=";
    };
    sourceRoot = "t3-${t3codeVersion}-linux-x64";

    dontConfigure = true;
    dontBuild = true;
    dontCheck = true;
    dontFixup = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/libexec/t3code" "$out/bin"
      # Keep the Bun-compiled ELF byte-for-byte intact and beside its client
      # assets. Patchelf changes this executable's embedded payload offsets.
      cp -a . "$out/libexec/t3code/"
      chmod 0755 "$out/libexec/t3code/t3"
      ln -s "$out/libexec/t3code/t3" "$out/bin/t3"
      runHook postInstall
    '';
  };

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

  startDirect = pkgs.writeShellScript "t3code-start-tailscale-direct" ''
    set -euo pipefail

    tailnet_ip="$(${pkgs.tailscale}/bin/tailscale ip -4 | ${pkgs.coreutils}/bin/head -n 1)"
    if [[ ! "$tailnet_ip" =~ ^100\. ]]; then
      echo "Could not determine this host's Tailscale IPv4 address" >&2
      exit 1
    fi

    exec ${t3code}/bin/t3 serve --host "$tailnet_ip" --port 3773
  '';

  startCommand =
    if t3codeTransport == "tailscale-serve" then
      "${t3code}/bin/t3 serve --host 127.0.0.1 --port 3773 --tailscale-serve"
    else
      startDirect;
in
{
  assertions = [
    {
      assertion = builtins.elem t3codeTransport [
        "tailscale-serve"
        "tailscale-direct"
      ];
      message = "t3codeTransport must be tailscale-serve or tailscale-direct";
    }
  ];

  # Nix owns the executable and service definition; T3 owns mutable pairing,
  # provider, and session state under ~/.t3.
  home.packages = [ t3code ];

  systemd.user.services.t3code = {
    Unit = {
      Description = "T3 Code remote server";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };

    Service = {
      # tailscale-serve publishes loopback through private HTTPS. The direct
      # fallback binds only the host's 100.x tailnet address, never its public
      # interface; Tailscale still encrypts and authorizes the traffic.
      ExecStartPre = waitForTailscale;
      ExecStart = startCommand;
      Environment = [
        "T3CODE_HOME=${homeDirectory}/.t3"
        "HOME=${homeDirectory}"
        "PATH=${managedUserPath}"
      ];
      WorkingDirectory = homeDirectory;
      Restart = "always";
      RestartSec = "5s";
      # T3 prints an initial pairing token on stdout. Do not persist that
      # credential in the user journal; generate explicit one-time links with
      # `t3 pair` instead. Keep stderr for operational failures.
      StandardOutput = "null";
      StandardError = "journal";
      UMask = "0077";
      TimeoutStopSec = "15s";
    };

    Install.WantedBy = [ "default.target" ];
  };
}
