{
  lib,
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
  piSkillAssertions = map (skill: {
    assertion = builtins.pathExists skill.path && builtins.pathExists "${skill.path}/SKILL.md";
    message = "Remote ${skill.groupName} skill '${skill.name}' is missing or has no SKILL.md at ${skill.path}. Update nix/home/remote-skills.nix.";
  }) piSkillSources;
in
{
  assertions = piSkillAssertions;

  home.activation.agentConfigs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        remove_path() {
          target="$1"
          if [ -e "$target" ]; then
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
        link_optional_path "${agentsDir}/pi/models.json" "$HOME/.pi/agent/models.json"
        link_optional_path "${agentsDir}/pi/mcp.json" "$HOME/.pi/agent/mcp.json"
        link_optional_path "${agentsDir}/pi/themes" "$HOME/.pi/agent/themes"
        link_optional_path "${agentsDir}/pi/extensions" "$HOME/.pi/agent/extensions"

        remove_path "$HOME/.pi/agent/skills"
        mkdir -p "$HOME/.pi/agent/skills"
        deploy_remote_skill_specs '${piSkillSpecs}' "$HOME/.pi/agent/skills"
        deploy_local_skill_dir "${agentsDir}/skills" "$HOME/.pi/agent/skills"
        deploy_local_skill_dir "${agentsDir}/pi/skills" "$HOME/.pi/agent/skills"
  '';

  home.activation.herdrPiIntegration = lib.hm.dag.entryAfter [ "agentConfigs" "installPackages" ] ''
    if command -v herdr >/dev/null 2>&1 && [ -d "$HOME/.pi/agent/extensions" ]; then
      herdr integration install pi >/dev/null 2>&1 || true
    fi
  '';
}
