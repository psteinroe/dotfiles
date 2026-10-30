# Dotfiles

Nix-managed Mac and Linux development environments. T3 Code is the daily UI;
Pi and Neovim remain available. macOS uses nix-darwin + Home Manager. Existing
NixOS machines are the default remote target; standalone Home Manager is optional.

## Mac

```sh
curl -fsSL https://raw.githubusercontent.com/psteinroe/dotfiles/main/bootstrap.sh | bash
rebuild       # apply checked-in configuration
rebuild -u    # deliberately update pinned inputs first
```

AeroSpace assigns T3 to workspace 1 (`alt-enter`), Chrome/Safari to 2 and
floating Ghostty to 3 (`alt-shift-enter`), using native rules and layouts.

## Existing remotes

Run from the Mac, naming the SSH destination every time. Nothing creates,
reimages or reboots machines. SSH as the existing development user. NixOS
switches and initial OS setup need passwordless sudo. Home Manager can use
admin-prepared Nix/cache, Tailscale and user lingering without sudo (on NixOS,
`programs.nix-ld` is also needed for upstream T3). Linux
x86_64 and ARM64 are supported where packages exist.

```sh
remote setup user@host                  # already-installed NixOS
remote setup user@host --home-manager   # existing systemd Linux; Git/curl/Tailscale required
remote deploy user@host                 # fast-forward dotfiles and switch
remote status user@host                 # checkout, service, HTTP readiness
remote shell user@host
remote connect user@host                # one-time T3 pairing link; open in the Mac/mobile app
```

Setup uses `~/Developer/dotfiles` and records its mode/target under
`~/.config/dotfiles`. Home Manager setup installs Nix if missing. NixOS setup
wraps `/etc/nixos/configuration.nix` without replacing hardware, boot or SSH
configuration. For an existing NixOS **flake**, add this input/module to it:

```nix
inputs.dotfiles.url = "git+file:///home/psteinroe/Developer/dotfiles";
# In the host's modules list:
dotfiles.nixosModules.remote
{ dotfiles.remote.user = "psteinroe"; }
```

Then use `remote setup user@host --nixos-flake /etc/nixos#hostname`. The named
flake remains host-owned. Use `--ref BRANCH` for a deliberate non-main deployment.
Deploy stops on dirty checkouts (including UI settings) or divergent history;
commit/stash first. `--force` explicitly discards tracked **and untracked** files.
Switches restart T3 and may interrupt active work. No automatic deployments run.
The prebuilt agent packages use the pinned Numtide binary cache.

Tailscale must be enrolled before connecting. T3 binds only its tailnet IPv4
address on port 3773: plain HTTP inside Tailscale's encrypted, authorized
transport, never a public listener. Check failures with
`journalctl --user -u t3code`. No Funnel or public relay is configured.

## T3 and authentication

`agents/t3/settings.json` and Pi settings remain live symlinks into the checkout;
UI edits intentionally appear as Git diffs. Linux switches add the eight shared
projects in `nix/home/t3code.nix` under `~/Developer/t3` without replacing clones.
Claude Code/Codex come from `llm-agents.nix`; Executor registration is add-only.
Repository actions run the checked-in `t3.json` hooks through `t3-repo-action`.

```sh
remote auth user@host gh
remote auth user@host mcp executor                  # Pi
remote auth user@host mcp executor --client claude
remote auth user@host mcp executor --client codex
remote auth user@host aws                           # also gcloud, azure, infisical, exa
```

MCP/GitHub logins are independent on each remote. Approval opens in the Mac
browser; loopback callbacks are forwarded when supported, with manual URL
pasting as fallback. Tokens stay remote. Cloud credentials and plain API keys
can be transferred over SSH with private file permissions; MCP/provider/GitHub
OAuth is never copied. Use the account intended for the named machine. Setup
creates a host-local SSH signing key; register its public key with GitHub if needed.

T3 release versions/hashes live in `nix/t3code-release.nix`; edit them manually.
Align desktop/mobile versions before upgrading the server. A version-changing
`remote deploy` requires `--allow-t3-update`: it stops T3 and backs up `~/.t3`
before switching. A database-migrating downgrade also needs the matching state
backup; rolling back Nix alone is insufficient.

## Personal CLIProxy

The independent, owner-scoped Pi (`nixosConfigurations.cliproxy`) serves
[CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) privately at
`https://cliproxy-psteinroe.tail649856.ts.net:8317`. Each owner needs their own
machine, tag, accounts and keys; this is not a team subscription pool. Use only
your own accounts, and Claude subscriptions only through Claude Code.

Build with Actions → **pi-images**, flash the `cliproxy-sd-image` artifact, and
put a one-use, pre-approved `tag:cliproxy-psteinroe` Tailscale auth key in
`tailscale-authkey` on the FAT partition. Boot over Ethernet; the key is deleted
after enrollment. Tailnet grants/sharing are managed in getmateo/devboxes.

On the work Mac, open `/management.html` on that endpoint. Copy its management
key privately, then authorize your own provider accounts in the UI:

```sh
ssh psteinroe@cliproxy-psteinroe.tail649856.ts.net \
  'cat /var/lib/cliproxyapi/management-key' | pbcopy
```

Claude uses the server root; Codex uses `/v1`. Clients share the API access key,
not the management key. **Client configuration/key deployment and Claude Bridge
replacement remain a separate PR**; this cleanup does not cut clients over.
Current Pi/Worker therefore retain Claude Bridge until that replacement lands.

The Pi never updates itself or compiles locally. Edit the server version/hash in
`nix/nixos/cliproxy/cliproxyapi.nix`, build elsewhere and switch manually,
preserving `/var/lib/cliproxyapi` and `/var/lib/tailscale`. Reflashing loses both.
Nix generates `config.yaml` on service start; change routing in Nix, not the UI.
Office routing stays until a separately verified client cutover.

## License

MIT. Retained extensions include their upstream licenses and attribution.
