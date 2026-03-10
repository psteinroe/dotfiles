{
  config,
  lib,
  pkgs,
  inputs,
  system,
  ...
}:

let
  dotfiles = "${config.home.homeDirectory}/Developer/dotfiles";
  agentsDir = "${dotfiles}/agents";
  claude-code = inputs.claude-code.packages.${system};
  claude-bin = "${claude-code.default}/bin/claude";
in
{
  home.activation.agentConfigs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    sync_optional_file() {
      src="$1"
      dst="$2"
      if [ -f "$src" ]; then
        cp -f "$src" "$dst"
      else
        rm -f "$dst"
      fi
    }

    # === Claude Code ===
    mkdir -p "$HOME/.claude"

    sync_optional_file "${agentsDir}/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
    sync_optional_file "${agentsDir}/claude/settings.json" "$HOME/.claude/settings.json"
    sync_optional_file "${agentsDir}/claude/file-suggestion.sh" "$HOME/.claude/file-suggestion.sh"
    if [ -f "$HOME/.claude/file-suggestion.sh" ]; then
      chmod +x "$HOME/.claude/file-suggestion.sh"
    fi

    # Deploy hooks
    rm -rf "$HOME/.claude/hooks"
    mkdir -p "$HOME/.claude/hooks"
    if [ -d "${agentsDir}/claude/hooks" ]; then
      for hook in "${agentsDir}"/claude/hooks/*.sh; do
        [ -f "$hook" ] || continue
        cp -f "$hook" "$HOME/.claude/hooks/"
        chmod +x "$HOME/.claude/hooks/$(basename "$hook")"
      done
    fi

    # Deploy skills in Claude's format (skills/name/SKILL.md)
    rm -rf "$HOME/.claude/skills"
    mkdir -p "$HOME/.claude/skills"
    if [ -d "${agentsDir}/claude/skills" ]; then
      for skill in "${agentsDir}"/claude/skills/*.md; do
        [ -f "$skill" ] || continue
        name=$(basename "$skill" .md)
        mkdir -p "$HOME/.claude/skills/$name"
        cp "$skill" "$HOME/.claude/skills/$name/SKILL.md"
      done
    fi

    # Install Claude plugins from declarative plugins.txt
    plugins_file="${agentsDir}/claude/plugins.txt"
    if [ -f "$plugins_file" ]; then
      section=""
      while IFS= read -r line || [ -n "$line" ]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*$ ]] && continue
        if [[ "$line" =~ ^#\ (.+) ]]; then
          section="''${BASH_REMATCH[1]}"
          continue
        fi
        case "$section" in
          marketplaces)
            ${claude-bin} plugin marketplace add "$line" 2>/dev/null || true
            ;;
          plugins)
            ${claude-bin} plugin install "$line" 2>/dev/null || true
            ;;
          mcps)
            name="''${line%%:*}"
            cmd="''${line#*:}"
            ${claude-bin} mcp add "$name" --scope user -- $cmd 2>/dev/null || true
            ;;
        esac
      done < "$plugins_file"
    fi

    # === OpenCode ===
    mkdir -p "$HOME/.config/opencode"

    sync_optional_file "${agentsDir}/opencode/AGENTS.md" "$HOME/.config/opencode/AGENTS.md"
    sync_optional_file "${agentsDir}/opencode/opencode.json" "$HOME/.config/opencode/opencode.json"

    # Deploy skills as plain .md files
    rm -rf "$HOME/.config/opencode/skills"
    mkdir -p "$HOME/.config/opencode/skills"
    if [ -d "${agentsDir}/opencode/skills" ]; then
      for skill in "${agentsDir}"/opencode/skills/*.md; do
        [ -f "$skill" ] || continue
        cp -f "$skill" "$HOME/.config/opencode/skills/"
      done
    fi

    # Install OpenCode plugins from declarative plugins.txt
    if command -v opencode &> /dev/null && command -v pnpx &> /dev/null; then
      plugins_file="${agentsDir}/opencode/plugins.txt"
      if [ -f "$plugins_file" ]; then
        section=""
        while IFS= read -r line || [ -n "$line" ]; do
          [[ -z "$line" || "$line" =~ ^[[:space:]]*$ ]] && continue
          if [[ "$line" =~ ^#\ (.+) ]]; then
            section="''${BASH_REMATCH[1]}"
            continue
          fi
          case "$section" in
            plugins)
              pnpx -y "$line" 2>/dev/null || true
              ;;
          esac
        done < "$plugins_file"
      fi
    fi

    # === Codex ===
    mkdir -p "$HOME/.codex"

    sync_optional_file "${agentsDir}/codex/AGENTS.md" "$HOME/.codex/AGENTS.md"
    sync_optional_file "${agentsDir}/codex/config.toml" "$HOME/.codex/config.toml"

    # Deploy skills as plain .md files
    rm -rf "$HOME/.codex/skills"
    mkdir -p "$HOME/.codex/skills"
    if [ -d "${agentsDir}/codex/skills" ]; then
      for skill in "${agentsDir}"/codex/skills/*.md; do
        [ -f "$skill" ] || continue
        cp -f "$skill" "$HOME/.codex/skills/"
      done
    fi

    # === Pi ===
    mkdir -p "$HOME/.pi/agent"

    sync_optional_file "${agentsDir}/pi/AGENTS.md" "$HOME/.pi/agent/AGENTS.md"
    sync_optional_file "${agentsDir}/pi/SYSTEM.md" "$HOME/.pi/agent/SYSTEM.md"
    sync_optional_file "${agentsDir}/pi/settings.json" "$HOME/.pi/agent/settings.json"
    sync_optional_file "${agentsDir}/pi/mcp.json" "$HOME/.pi/agent/mcp.json"

    # Deploy extensions as .ts files
    rm -rf "$HOME/.pi/agent/extensions"
    mkdir -p "$HOME/.pi/agent/extensions"
    if [ -d "${agentsDir}/pi/extensions" ]; then
      for extension in "${agentsDir}"/pi/extensions/*.ts; do
        [ -f "$extension" ] || continue
        cp -f "$extension" "$HOME/.pi/agent/extensions/"
      done
    fi

    # Deploy skills in Pi's format (skills/name/SKILL.md — same as Claude)
    rm -rf "$HOME/.pi/agent/skills"
    mkdir -p "$HOME/.pi/agent/skills"
    if [ -d "${agentsDir}/pi/skills" ]; then
      for skill in "${agentsDir}"/pi/skills/*.md; do
        [ -f "$skill" ] || continue
        name=$(basename "$skill" .md)
        mkdir -p "$HOME/.pi/agent/skills/$name"
        cp "$skill" "$HOME/.pi/agent/skills/$name/SKILL.md"
      done
    fi
  '';
}
