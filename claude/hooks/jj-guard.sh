#!/bin/bash
# PreToolUse hook: Block git commands in jj repos
# Exit 2 = block with message to Claude
# Passthrough: read-only commands + submodule

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Skip if not a git command
[[ ! "$COMMAND" =~ ^git[[:space:]] ]] && exit 0

# Check if we're in a jj repo
jj root >/dev/null 2>&1 || exit 0

# Allow passthrough commands
case "$COMMAND" in
  "git status"*|"git diff"*|"git log"*|"git show"*) exit 0 ;;  # read-only
  "git submodule"*) exit 0 ;;  # jj doesn't handle submodules well
esac

# Block and suggest jj alternative (prefer aliases/functions)
case "$COMMAND" in
  "git add"*) ALT="(not needed - jj auto-tracks)" ;;
  "git commit"*) ALT="jjc 'message' (alias for jj commit -m)" ;;
  "git push"*) ALT="jj git push" ;;
  "git fetch"*) ALT="jjf (alias for jj git fetch)" ;;
  "git pull"*) ALT="jjf && jjr (fetch + rebase to trunk)" ;;
  "git checkout -b"*) ALT="jjcreate <name> (creates workspace + bookmark + deps)" ;;
  "git checkout"*) ALT="jjcheckout <branch|pr#> (creates workspace)" ;;
  "git clone"*) ALT="jjclone <url> (creates jj repo with workspaces)" ;;
  "git rebase"*) ALT="jjr (alias for jj rebase -d trunk())" ;;
  "git branch"*) ALT="jj bookmark list" ;;
  "git merge"*) ALT="jj rebase -d <target>" ;;
  "git reset"*) ALT="jj restore or jj abandon" ;;
  "git stash"*) ALT="(not needed - jj auto-tracks working copy)" ;;
  "git worktree"*) ALT="jjlist, jjcreate, jjclean (workspace functions)" ;;
  *) ALT="check jj docs or jj* aliases" ;;
esac

echo "jj repo detected. Use: $ALT" >&2
exit 2
