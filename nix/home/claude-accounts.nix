# Extra Claude Code accounts from agents/claude/accounts.json, each with its own
# CLAUDE_CONFIG_DIR. ~/.claude is the default account and needs no variable.
{ lib }:

lib.mapAttrsToList (name: dir: {
  inherit name;
  dir = lib.removePrefix "~/" dir;
}) (lib.filterAttrs (_: dir: dir != "~/.claude") (lib.importJSON ../../agents/claude/accounts.json))
