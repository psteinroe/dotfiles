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
configuration, but the whole OS then builds from this flake's pinned
`nixpkgs-unstable` instead of the host's channel. Home Manager follows that pin.
For an existing NixOS **flake**, add this input/module to it:

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
A switch restarts T3, interrupting its agents, only when its address or the
dotfiles drop-in changes. No automatic deployments run.
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

[tstack](https://github.com/t3dotgg/tstack) is pinned as a flake input. Each
switch copies its skills into the standard `~/.claude/skills` and
`~/.codex/skills` directories, so T3 sessions get them. Skills dropped upstream
are removed; unrelated skills in those directories stay. Update with
`nix flake update tstack`.

T3 keeps itself up to date; dotfiles pins no version. The Mac app updates
itself (or use Check for Updates), and T3's apps update a server on another
version to their own. On Linux, setup installs T3 with its official installer at
the Mac app's version and runs `t3 service install`; both are skipped once
present. `t3 update` on the host does the same by hand. A dotfiles drop-in
(`~/.config/systemd/user/t3code.service.d/dotfiles.conf`) only adds the agent
`PATH`, nix-ld and the tailnet address. T3 downgrades can't undo database
migrations, so back up `~/.t3` before one.

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

### Clients

Clients use the API access key, never the management key. Each machine keeps it
in `~/.config/cliproxy/access-key` (0600); no config file contains it. Put it on
the Mac, then send it to each remote:

```sh
(umask 077; mkdir -p ~/.config/cliproxy && ssh psteinroe@cliproxy-psteinroe.tail649856.ts.net \
  'cat /var/lib/cliproxyapi/access-key' > ~/.config/cliproxy/access-key)
rebuild                          # Mac
remote auth user@host cliproxy   # any remote, with or without Home Manager
```

`scripts/cliproxy-clients.sh` runs on every switch and through `remote auth`.
It points the standard homes at the proxy and keeps everything else in them:

- Claude Code (`~/.claude/settings.json`): `ANTHROPIC_BASE_URL` plus an
  `apiKeyHelper`. T3, the CLI and Pi's Claude Bridge all use it, so Claude
  subscriptions still run only through Claude Code.
- Codex (`~/.codex/config.toml`): a `cliproxy` provider at `/v1`.
- Pi (`~/.pi/agent/models.json`): the built-in `openai` provider at `/v1`, for
  the OpenAI subagents. A stored Pi login wins, so run `/logout openai` in Pi
  and switch again.

T3 needs one Claude and one Codex instance on those standard homes; the proxy
chooses the account. Bridge compaction summaries ignore user settings and use
the existing Claude Code login directly, so keep that login.

The Pi never updates itself or compiles locally. Edit the server version/hash in
`nix/nixos/cliproxy/cliproxyapi.nix`, build elsewhere and switch manually,
preserving `/var/lib/cliproxyapi` and `/var/lib/tailscale`. Reflashing loses both.
Nix generates `config.yaml` on service start; change routing in Nix, not the UI.
Office routing stays until a separately verified client cutover.

## License

MIT. Retained extensions include their upstream licenses and attribution.
