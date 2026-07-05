# Tailscale Remote Dev

Current state: Tailscale is the primary remote-dev transport.

## Remote target

- Remote node: `psteinroe-dev`.
- Tailscale IP: `100.73.58.101`.
- `rdev` SSH target logs in directly as `psteinroe`.
- `rdev-exe` keeps the exe.dev gateway as bootstrap/recovery only.

## Daily commands

```bash
rdev hellomateo main     # native Herdr remote session over Tailscale
rrebuild                 # pull dotfiles and rebuild remote Home Manager
ssh rdev                 # plain direct shell as psteinroe
ssh rdev-exe             # recovery path through exe.dev gateway
```

## SSH config shape

```sshconfig
Host rdev-exe
  HostName psteinroe-dev.exe.xyz
  User exedev

Host rdev
  HostName 100.73.58.101
  User psteinroe
```

## Validation

```bash
tailscale status
tailscale ping psteinroe-dev
ssh rdev 'id; echo $HOME; hostname'
ssh -T rdev 'for i in $(seq 1 10); do date; sleep 1; done'
rdev dotfiles main
```

Expected direct SSH identity:

```text
uid=1001(psteinroe)
/home/psteinroe
```

## Notes

- Tailscale was installed via Nix/Home Manager; the remote daemon is enabled with systemd.
- Current ping may route via DERP if direct UDP is unavailable; SSH/Herdr still works.
- Mosh remains deferred until Tailscale UDP is validated.
- Use `rrebuild [host]` for remote rebuilds.
