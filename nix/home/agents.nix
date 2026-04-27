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
  remoteSkills = import ./remote-skills.nix { inherit inputs; };
  serializeSkillSpecs = skills:
    lib.concatMapStringsSep "\n" (skill: "${skill.name}\t${skill.path}") skills;
  remoteSkillSpecs = {
    claude = serializeSkillSpecs (remoteSkills.shared ++ remoteSkills.claude);
    codex = serializeSkillSpecs (remoteSkills.shared ++ remoteSkills.codex);
    opencode = serializeSkillSpecs (remoteSkills.shared ++ remoteSkills.opencode);
    pi = serializeSkillSpecs (remoteSkills.shared ++ remoteSkills.pi);
  };
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

    deploy_skill_bundle() {
      src="$1"
      dst="$2"
      name=$(basename "$src")

      [ -d "$src" ] || return
      [ -f "$src/SKILL.md" ] || return

      rm -rf "$dst/$name"
      cp -R "$src" "$dst/$name"
    }

    deploy_local_skill_dir() {
      src_dir="$1"
      dst="$2"

      [ -d "$src_dir" ] || return

      for skill in "$src_dir"/*; do
        [ -d "$skill" ] || continue
        deploy_skill_bundle "$skill" "$dst"
      done
    }

    deploy_remote_skill_specs() {
      specs="$1"
      dst="$2"

      [ -n "$specs" ] || return

      while IFS=$'\t' read -r name src; do
        [ -n "$name" ] || continue
        [ -d "$src" ] || continue
        rm -rf "$dst/$name"
        cp -R "$src" "$dst/$name"
      done <<EOF
$specs
EOF
    }

    deploy_skills() {
      agent="$1"
      dst="$2"
      remote_specs="$3"

      rm -rf "$dst"
      mkdir -p "$dst"

      deploy_remote_skill_specs "$remote_specs" "$dst"
      deploy_local_skill_dir "${agentsDir}/skills" "$dst"
      deploy_local_skill_dir "${agentsDir}/$agent/skills" "$dst"
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

    # Deploy pinned upstream skills first, then local shared skills, then
    # Claude-specific overrides. All agents use the standard skills bundle
    # layout: skills/<name>/SKILL.md (+ optional scripts/references).
    deploy_skills "claude" "$HOME/.claude/skills" '${remoteSkillSpecs.claude}'

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

    # Deploy pinned upstream skills first, then local shared skills, then
    # OpenCode-specific overrides.
    deploy_skills "opencode" "$HOME/.config/opencode/skills" '${remoteSkillSpecs.opencode}'

    # Deploy plugins as .ts files
    rm -rf "$HOME/.config/opencode/plugins"
    mkdir -p "$HOME/.config/opencode/plugins"
    if [ -d "${agentsDir}/opencode/plugins" ]; then
      for plugin in "${agentsDir}"/opencode/plugins/*.ts; do
        [ -f "$plugin" ] || continue
        cp -f "$plugin" "$HOME/.config/opencode/plugins/"
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

    # Deploy pinned upstream skills first, then local shared skills, then
    # Codex-specific overrides.
    deploy_skills "codex" "$HOME/.codex/skills" '${remoteSkillSpecs.codex}'

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

    # Deploy pinned upstream skills first, then local shared skills, then
    # Pi-specific overrides.
    deploy_skills "pi" "$HOME/.pi/agent/skills" '${remoteSkillSpecs.pi}'
  '';
}
