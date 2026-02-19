{
  config,
  lib,
  pkgs,
  ...
}:

let
  dotfiles = "${config.home.homeDirectory}/Developer/dotfiles";
  agentsDir = "${dotfiles}/agents";
in
{
  home.activation.agentConfigs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # === Claude Code ===
    mkdir -p $HOME/.claude/skills

    cp -f ${agentsDir}/claude/CLAUDE.md $HOME/.claude/CLAUDE.md
    cp -f ${agentsDir}/claude/settings.json $HOME/.claude/settings.json
    cp -f ${agentsDir}/claude/file-suggestion.sh $HOME/.claude/file-suggestion.sh
    chmod +x $HOME/.claude/file-suggestion.sh

    # Deploy skills in Claude's format (skills/name/SKILL.md)
    rm -rf $HOME/.claude/skills
    mkdir -p $HOME/.claude/skills
    for skill in ${agentsDir}/claude/skills/*.md; do
      name=$(basename "$skill" .md)
      mkdir -p "$HOME/.claude/skills/$name"
      cp "$skill" "$HOME/.claude/skills/$name/SKILL.md"
    done

    # Install Claude plugins from declarative plugins.txt
    if command -v claude &> /dev/null; then
      plugins_file="${agentsDir}/claude/plugins.txt"
      section=""
      while IFS= read -r line || [ -n "$line" ]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*$ ]] && continue
        if [[ "$line" =~ ^#\ (.+) ]]; then
          section="''${BASH_REMATCH[1]}"
          continue
        fi
        case "$section" in
          marketplaces)
            claude plugin marketplace add "$line" 2>/dev/null || true
            ;;
          plugins)
            claude plugin install "$line" 2>/dev/null || true
            ;;
          mcps)
            name="''${line%%:*}"
            cmd="''${line#*:}"
            claude mcp add "$name" --scope user -- $cmd 2>/dev/null || true
            ;;
        esac
      done < "$plugins_file"
    fi

    # === OpenCode ===
    mkdir -p $HOME/.config/opencode

    cp -f ${agentsDir}/opencode/AGENTS.md $HOME/.config/opencode/AGENTS.md
    cp -f ${agentsDir}/opencode/opencode.json $HOME/.config/opencode/opencode.json

    # Deploy skills as plain .md files
    rm -rf $HOME/.config/opencode/skills
    mkdir -p $HOME/.config/opencode/skills
    cp -f ${agentsDir}/opencode/skills/*.md $HOME/.config/opencode/skills/

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
    mkdir -p $HOME/.codex/skills

    cp -f ${agentsDir}/codex/AGENTS.md $HOME/.codex/AGENTS.md
    cp -f ${agentsDir}/codex/config.toml $HOME/.codex/config.toml

    # Deploy skills as plain .md files
    rm -rf $HOME/.codex/skills
    mkdir -p $HOME/.codex/skills
    cp -f ${agentsDir}/codex/skills/*.md $HOME/.codex/skills/

    # === Pi ===
    mkdir -p $HOME/.pi/agent

    cp -f ${agentsDir}/pi/AGENTS.md $HOME/.pi/agent/AGENTS.md
    cp -f ${agentsDir}/pi/SYSTEM.md $HOME/.pi/agent/SYSTEM.md
    cp -f ${agentsDir}/pi/settings.json $HOME/.pi/agent/settings.json
    cp -f ${agentsDir}/pi/mcp.json $HOME/.pi/agent/mcp.json

    # Deploy skills in Pi's format (skills/name/SKILL.md — same as Claude)
    rm -rf $HOME/.pi/agent/skills
    mkdir -p $HOME/.pi/agent/skills
    for skill in ${agentsDir}/pi/skills/*.md; do
      name=$(basename "$skill" .md)
      mkdir -p "$HOME/.pi/agent/skills/$name"
      cp "$skill" "$HOME/.pi/agent/skills/$name/SKILL.md"
    done
  '';
}
