# CLIProxyAPI on the cliproxy Pi: every Claude and Codex subscription logs in here only,
# and other machines reach it at https://<hostName>.<tailnet>.ts.net:8317 via `tailscale serve`.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  cliproxyapiVersion = "8.0.44";
  # The no-plugin build is a static Go binary; the plugin build links glibc
  # dynamically for Go plugins, which stay disabled here.
  cliproxyapi = pkgs.stdenvNoCC.mkDerivation {
    pname = "cliproxyapi";
    version = cliproxyapiVersion;

    src = pkgs.fetchurl {
      url = "https://github.com/router-for-me/CLIProxyAPI/releases/download/v${cliproxyapiVersion}/CLIProxyAPI_${cliproxyapiVersion}_linux_aarch64_no-plugin.tar.gz";
      hash = "sha256-gWl6KhShw+LLJ7szjJT63tSFXF3EGOUCzPP6mekX1Kw=";
    };
    sourceRoot = ".";

    dontConfigure = true;
    dontBuild = true;
    dontCheck = true;
    dontFixup = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 cli-proxy-api "$out/bin/cli-proxy-api"
      install -Dm644 config.example.yaml "$out/share/cliproxyapi/config.example.yaml"
      runHook postInstall
    '';
  };

  stateDir = "/var/lib/cliproxyapi";
  configFile = "${stateDir}/config.yaml";
  port = 8317;

  # Keys are filled in at service start from files in the state directory, so
  # neither Git nor the store holds them. Keys follow the upstream v8
  # config.example.yaml. The server rewrites secret-key as a bcrypt hash on load.
  configTemplate = pkgs.writeText "cliproxyapi-config.yaml" ''
    config-version: 8
    server:
      host: "127.0.0.1"
      port: ${toString port}
      trusted-proxies: ["127.0.0.1", "::1"]
    management:
      allow-remote: true
      secret-key: "@MANAGEMENT_KEY@"
    access:
      api-keys: ["@ACCESS_KEY@"]
    routing:
      strategy: "round-robin"
      session-affinity: true
      session-affinity-ttl: "1h"
      retry:
        request-retry: 3
        max-retry-interval: 30
    oauth:
      auth-dir: "${stateDir}/auths"
  '';

  prepare = pkgs.writeShellScript "cliproxyapi-prepare" ''
    set -euo pipefail
    PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.gnused
      ]
    }
    umask 077
    cd ${stateDir}

    for key in access-key management-key; do
      if [ ! -s "$key" ]; then
        head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' >"$key.tmp"
        mv "$key.tmp" "$key"
      fi
    done
    mkdir -p auths

    # printf is a builtin, so the keys never show up in a process's arguments
    printf 's/@ACCESS_KEY@/%s/\ns/@MANAGEMENT_KEY@/%s/\n' "$(<access-key)" "$(<management-key)" >config.sed
    sed -f config.sed ${configTemplate} >config.yaml.tmp
    rm config.sed
    mv config.yaml.tmp config.yaml
  '';

  # Logins run as the service user against the same config and auth dir, e.g.
  # `cliproxy -claude-login -no-browser` or `cliproxy -codex-device-login`
  cliproxy = pkgs.writeShellScriptBin "cliproxy" ''
    if [ "$(id -u)" = 0 ]; then
      exec ${pkgs.util-linux}/bin/runuser -u ${username} -- "$0" "$@"
    fi
    cd ${stateDir} || exit 1
    exec ${cliproxyapi}/bin/cli-proxy-api -config ${configFile} "$@"
  '';

  tailscale = config.services.tailscale.package;
in
{
  environment.systemPackages = [ cliproxy ];

  systemd.services.cliproxyapi = {
    description = "CLIProxyAPI";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    startLimitIntervalSec = 300;
    startLimitBurst = 5;

    serviceConfig = {
      User = username;
      Group = "users";
      StateDirectory = "cliproxyapi";
      StateDirectoryMode = "0700";
      WorkingDirectory = stateDir;
      ExecStartPre = prepare;
      ExecStart = "${cliproxyapi}/bin/cli-proxy-api -config ${configFile}";
      # Soft limit so Go collects garbage before the Pi's 1 GB fills up
      Environment = [ "GOMEMLIMIT=384MiB" ];
      Restart = "always";
      RestartSec = "5s";
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "full";
    };
  };

  # Publishes the proxy on the tailnet over HTTPS once Tailscale is logged in. Not a
  # oneshot: it waits for `tailscale up` (and for HTTPS to be enabled in the tailnet),
  # which must block neither boot nor nixos-rebuild. Serve config persists in
  # tailscaled's state; rerunning the same command is a no-op.
  systemd.services.cliproxyapi-tailscale-serve = {
    description = "Serve CLIProxyAPI on the tailnet over HTTPS";
    wantedBy = [ "multi-user.target" ];
    after = [
      "tailscaled.service"
      "cliproxyapi.service"
    ];
    wants = [ "tailscaled.service" ];
    path = [
      tailscale
      pkgs.jq
    ];
    script = ''
      until tailscale status --json 2>/dev/null | jq -e '.BackendState == "Running"' >/dev/null; do
        sleep 10
      done
      tailscale serve --bg --https=${toString port} http://127.0.0.1:${toString port}
    '';
    serviceConfig = {
      Type = "simple";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "30s";
    };
  };
}
