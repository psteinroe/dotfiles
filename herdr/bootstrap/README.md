# Herdr bootstrap hooks

Optional repo-specific pane bootstrap hooks live here as `<repo>.zsh`.

When `psteinroe.worktree-sync.bootstrap` runs, it exposes:

- `WS_PROJECT_NAME`
- `WS_PROJECT_ROOT`
- `WS_PROJECT_CWD`
- `WS_WORKTREE_ROOT`
- `HERDR_WORKSPACE_ID`
- `HERDR_PANE_ID`
- helper `_hws_split <source-pane> <right|down> <ratio> <label> [focus-0-or-1]`
- helper `_hws_default_bootstrap`

Hooks should be safe and idempotent. Prefer creating/renaming panes over starting
long-running processes automatically.
