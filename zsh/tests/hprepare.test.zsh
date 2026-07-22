#!/usr/bin/env zsh
set -euo pipefail

repo_root=${0:A:h:h:h}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

mkdir -p \
  "$fixture/home/Developer/example" \
  "$fixture/home/.config/herdr" \
  "$fixture/dotfiles/zsh/functions"
git -C "$fixture/home/Developer/example" init -q
print -r -- '[]' > "$fixture/home/.config/herdr/plugins.json"

cp "$repo_root/zsh/functions/_herdr_binary" "$fixture/dotfiles/zsh/functions/_herdr_binary"
print -r -- ':' > "$fixture/dotfiles/zsh/functions/hsyncworktrees"
cat > "$fixture/dotfiles/zsh/functions/_herdr_worktree_helpers" <<'EOF'
_h_repo_context() { return 0; }
_h_ensure_workspace() { return 0; }
EOF
cat > "$fixture/herdr" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$fixture/herdr"

HOME="$fixture/home" \
USER=test \
HERDR_BIN="$fixture/herdr" \
RDEV_DOTFILES="$fixture/dotfiles" \
  source "$repo_root/zsh/functions/hprepare" example

session_plugins="$fixture/home/.config/herdr/sessions/example/plugins.json"
[[ -L "$session_plugins" ]]
[[ $(readlink "$session_plugins") == ../../plugins.json ]]
[[ $(<"$session_plugins") == '[]' ]]

print 'hprepare named-session plugin registry test passed'
