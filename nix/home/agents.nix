{
  config,
  lib,
  pkgs,
  inputs,
  system,
  dotfilesPath,
  isDarwin ? false,
  ...
}:

let
  agentsDir = "${dotfilesPath}/agents";
  claudeCode = lib.attrByPath [ system "default" ] null inputs.claude-code.packages;
  claude-bin = if claudeCode != null then "${claudeCode}/bin/claude" else "claude";
  claudeSettings =
    if isDarwin then "${agentsDir}/claude/settings.json" else "${agentsDir}/claude/settings.linux.json";
  piSettings =
    if isDarwin then "${agentsDir}/pi/settings.json" else "${agentsDir}/pi/settings.linux.json";
  remoteSkills = import ./remote-skills.nix { inherit inputs; };
  serializeSkillSpecs =
    skills: lib.concatMapStringsSep "\n" (skill: "${skill.name}\t${skill.path}") skills;
  remoteSkillSpecs = {
    claude = serializeSkillSpecs (remoteSkills.shared ++ remoteSkills.claude);
    codex = serializeSkillSpecs (remoteSkills.shared ++ remoteSkills.codex);
    opencode = serializeSkillSpecs (remoteSkills.shared ++ remoteSkills.opencode);
    pi = serializeSkillSpecs (remoteSkills.shared ++ remoteSkills.pi);
  };
  remoteSkillSources =
    lib.concatMap (group: map (skill: skill // { inherit (group) groupName; }) group.skills)
      [
        {
          groupName = "shared";
          skills = remoteSkills.shared;
        }
        {
          groupName = "claude";
          skills = remoteSkills.claude;
        }
        {
          groupName = "codex";
          skills = remoteSkills.codex;
        }
        {
          groupName = "opencode";
          skills = remoteSkills.opencode;
        }
        {
          groupName = "pi";
          skills = remoteSkills.pi;
        }
      ];
  remoteSkillAssertions = map (skill: {
    assertion = builtins.pathExists skill.path && builtins.pathExists "${skill.path}/SKILL.md";
    message = "Remote ${skill.groupName} skill '${skill.name}' is missing or has no SKILL.md at ${skill.path}. Update nix/home/remote-skills.nix.";
  }) remoteSkillSources;
in
{
  assertions = remoteSkillAssertions;

  home.activation.agentConfigs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        remove_path() {
          target="$1"
          if [ -e "$target" ]; then
            chmod -R u+w "$target" 2>/dev/null || true
            rm -rf "$target"
          fi
        }

        sync_optional_file() {
          src="$1"
          dst="$2"
          if [ -f "$src" ]; then
            cp -f "$src" "$dst"
          else
            rm -f "$dst"
          fi
        }

        link_optional_path() {
          src="$1"
          dst="$2"
          if [ -e "$src" ]; then
            remove_path "$dst"
            ln -s "$src" "$dst"
          else
            remove_path "$dst"
          fi
        }

        deploy_skill_bundle() {
          src="$1"
          dst="$2"
          name=$(basename "$src")

          [ -d "$src" ] || return 0
          [ -f "$src/SKILL.md" ] || return 0

          remove_path "$dst/$name"
          cp -R "$src" "$dst/$name"
          chmod -R u+w "$dst/$name" 2>/dev/null || true
        }

        deploy_local_skill_dir() {
          src_dir="$1"
          dst="$2"

          [ -d "$src_dir" ] || return 0

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
            remove_path "$dst/$name"
            cp -R "$src" "$dst/$name"
            chmod -R u+w "$dst/$name" 2>/dev/null || true
          done <<EOF
    $specs
    EOF
        }

        deploy_skills() {
          agent="$1"
          dst="$2"
          remote_specs="$3"

          remove_path "$dst"
          mkdir -p "$dst"

          deploy_remote_skill_specs "$remote_specs" "$dst"
          deploy_local_skill_dir "${agentsDir}/skills" "$dst"
          deploy_local_skill_dir "${agentsDir}/$agent/skills" "$dst"
        }

        # === Claude Code ===
        mkdir -p "$HOME/.claude"

        sync_optional_file "${agentsDir}/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
        sync_optional_file "${claudeSettings}" "$HOME/.claude/settings.json"
        sync_optional_file "${agentsDir}/claude/file-suggestion.sh" "$HOME/.claude/file-suggestion.sh"
        if [ -f "$HOME/.claude/file-suggestion.sh" ]; then
          chmod +x "$HOME/.claude/file-suggestion.sh"
        fi

        # Deploy macOS-only hooks. Linux settings do not reference them.
        rm -rf "$HOME/.claude/hooks"
        mkdir -p "$HOME/.claude/hooks"
        if [ "${if isDarwin then "1" else "0"}" = "1" ] && [ -d "${agentsDir}/claude/hooks" ]; then
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
                if command -v ${claude-bin} >/dev/null 2>&1; then ${claude-bin} plugin marketplace add "$line" 2>/dev/null || true; fi
                ;;
              plugins)
                if command -v ${claude-bin} >/dev/null 2>&1; then ${claude-bin} plugin install "$line" 2>/dev/null || true; fi
                ;;
              mcps)
                name="''${line%%:*}"
                cmd="''${line#*:}"
                if command -v ${claude-bin} >/dev/null 2>&1; then ${claude-bin} mcp add "$name" --scope user -- $cmd 2>/dev/null || true; fi
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

        # Link local Pi files out-of-store so changing settings or adding an
        # extension is reflected after a Pi restart/reload, without needing a
        # Nix generation change just to copy files again.
        link_optional_path "${agentsDir}/pi/AGENTS.md" "$HOME/.pi/agent/AGENTS.md"
        link_optional_path "${agentsDir}/pi/SYSTEM.md" "$HOME/.pi/agent/SYSTEM.md"
        link_optional_path "${piSettings}" "$HOME/.pi/agent/settings.json"
        link_optional_path "${agentsDir}/pi/models.json" "$HOME/.pi/agent/models.json"
        link_optional_path "${agentsDir}/pi/mcp.json" "$HOME/.pi/agent/mcp.json"
        link_optional_path "${agentsDir}/pi/themes" "$HOME/.pi/agent/themes"
        link_optional_path "${agentsDir}/pi/extensions" "$HOME/.pi/agent/extensions"

        # Deploy pinned upstream skills first, then local shared skills, then
        # Pi-specific overrides.
        deploy_skills "pi" "$HOME/.pi/agent/skills" '${remoteSkillSpecs.pi}'
  '';
}
