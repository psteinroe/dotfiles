{
  config,
  lib,
  pkgs,
  inputs,
  dotfilesPath,
  isDarwin ? false,
  ...
}:

let
  agentsDir = "${dotfilesPath}/agents";
  piSettings =
    if isDarwin then "${agentsDir}/pi/settings.json" else "${agentsDir}/pi/settings.linux.json";
  remoteSkills = import ./remote-skills.nix { inherit inputs; };
  serializeSkillSpecs =
    skills: lib.concatMapStringsSep "\n" (skill: "${skill.name}\t${skill.path}") skills;
  piSkillSpecs = serializeSkillSpecs (remoteSkills.shared ++ remoteSkills.pi);
  piSkillSources = map (skill: skill // { groupName = "pi"; }) (
    remoteSkills.shared ++ remoteSkills.pi
  );
  # Called by the machine-wide actions in agents/t3/settings.json
  t3RepoAction = pkgs.writeShellApplication {
    name = "t3-repo-action";
    runtimeInputs = [ pkgs.jq ];
    text = builtins.readFile ../../agents/t3/t3-repo-action.sh;
  };
  piSkillAssertions = map (skill: {
    assertion = builtins.pathExists skill.path && builtins.pathExists "${skill.path}/SKILL.md";
    message = "Remote ${skill.groupName} skill '${skill.name}' is missing or has no SKILL.md at ${skill.path}. Update nix/home/remote-skills.nix.";
  }) piSkillSources;
in
{
  assertions = piSkillAssertions;

  home.packages = [ t3RepoAction ];

  home.activation.agentConfigs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        remove_path() {
          target="$1"
          if [ -e "$target" ] || [ -L "$target" ]; then
            chmod -R u+w "$target" 2>/dev/null || true
            rm -rf "$target"
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

        deploy_extension_dir() {
          src_dir="$1"
          dst="$2"

          remove_path "$dst"
          mkdir -p "$dst"

          [ -d "$src_dir" ] || return 0

          for extension in "$src_dir"/*; do
            if [ ! -e "$extension" ] && [ ! -L "$extension" ]; then
              continue
            fi
            ln -s "$extension" "$dst/$(basename "$extension")"
          done
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

        mkdir -p "$HOME/.pi/agent"
        link_optional_path "${agentsDir}/pi/AGENTS.md" "$HOME/.pi/agent/AGENTS.md"
        link_optional_path "${agentsDir}/pi/SYSTEM.md" "$HOME/.pi/agent/SYSTEM.md"
        link_optional_path "${piSettings}" "$HOME/.pi/agent/settings.json"
        link_optional_path "${agentsDir}/pi/provider-failover.json" "$HOME/.pi/agent/provider-failover.json"
        link_optional_path "${agentsDir}/pi/claude-bridge.json" "$HOME/.pi/agent/claude-bridge.json"
        link_optional_path "${agentsDir}/pi/models.json" "$HOME/.pi/agent/models.json"
        link_optional_path "${agentsDir}/pi/mcp.json" "$HOME/.pi/agent/mcp.json"
        link_optional_path "${agentsDir}/pi/themes" "$HOME/.pi/agent/themes"
        deploy_extension_dir "${agentsDir}/pi/extensions" "$HOME/.pi/agent/extensions"

        remove_path "$HOME/.pi/agent/skills"
        mkdir -p "$HOME/.pi/agent/skills"
        deploy_remote_skill_specs '${piSkillSpecs}' "$HOME/.pi/agent/skills"
        deploy_local_skill_dir "${agentsDir}/skills" "$HOME/.pi/agent/skills"
        deploy_local_skill_dir "${agentsDir}/pi/skills" "$HOME/.pi/agent/skills"

        # T3 Code writes settings changed in its UI through the link, back into the checkout
        mkdir -p "$HOME/.t3/userdata"
        link_optional_path "${agentsDir}/t3/settings.json" "$HOME/.t3/userdata/settings.json"
  '';

  # Registers Pi's executor MCP server with Claude Code (user scope, in ~/.claude and the
  # ~/.claude-hub config that hub-client points at the home hub) and Codex, which run under
  # T3 Code. Only adds a missing entry, so an existing one and its OAuth login stay untouched.
  # Codex's entry is appended directly: `codex mcp add` starts a blocking OAuth login.
  home.activation.agentMcpServers = lib.hm.dag.entryAfter [ "agentConfigs" "installPackages" ] ''
    bin="${config.home.profileDirectory}/bin"
    url=$(${pkgs.jq}/bin/jq -r '.mcpServers.executor.url // empty' "${agentsDir}/pi/mcp.json" 2>/dev/null)

    if [ -n "$url" ]; then
      # $1: the CLAUDE_CONFIG_DIR, empty for the default ~/.claude
      add_claude_executor() {
        claude_json="''${1:-$HOME}/.claude.json"
        [ -x "$bin/claude" ] || return 0
        ${pkgs.jq}/bin/jq -e '.mcpServers.executor' "$claude_json" >/dev/null 2>&1 && return 0
        if [ -n "$1" ]; then
          $DRY_RUN_CMD mkdir -p -m 700 "$1"
          $DRY_RUN_CMD env CLAUDE_CONFIG_DIR="$1" "$bin/claude" mcp add --scope user --transport http executor "$url"
        else
          $DRY_RUN_CMD "$bin/claude" mcp add --scope user --transport http executor "$url"
        fi || echo "warning: could not add the executor MCP server to Claude Code in ''${1:-~/.claude}" >&2
      }

      add_claude_executor ""
      add_claude_executor "$HOME/.claude-hub"

      if ! grep -q '^\[mcp_servers\.executor\]' "$HOME/.codex/config.toml" 2>/dev/null; then
        $DRY_RUN_CMD mkdir -p "$HOME/.codex"
        if [ -z "''${DRY_RUN:-}" ]; then
          printf '\n[mcp_servers.executor]\nurl = "%s"\n' "$url" >>"$HOME/.codex/config.toml"
        fi
      fi
    fi
  '';

  home.activation.herdrPiIntegration = lib.hm.dag.entryAfter [ "agentConfigs" "installPackages" ] ''
    if command -v herdr >/dev/null 2>&1 && [ -d "$HOME/.pi/agent/extensions" ]; then
      herdr integration install pi >/dev/null 2>&1 || true
    fi
  '';
}
