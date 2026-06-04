{ inputs }:
{
  # Shared upstream skills are pinned via flake.lock and updated explicitly with
  # `nix flake lock --update-input <input>` or `nix flake update`.
  shared = [
    {
      name = "agent-browser";
      path = "${inputs.agent-browser-skills}/skills/agent-browser";
      repo = "vercel-labs/agent-browser";
    }
    {
      name = "code-simplifier";
      path = "${inputs.getsentry-skills}/skills/code-simplifier";
      repo = "getsentry/skills";
    }
    {
      name = "grill-me";
      path = "${inputs.mattpocock-skills}/skills/productivity/grill-me";
      repo = "mattpocock/skills";
    }
    {
      name = "diagnose";
      path = "${inputs.mattpocock-skills}/skills/engineering/diagnose";
      repo = "mattpocock/skills";
    }
    {
      name = "grill-with-docs";
      path = "${inputs.mattpocock-skills}/skills/engineering/grill-with-docs";
      repo = "mattpocock/skills";
    }
    {
      name = "handoff";
      path = "${inputs.mattpocock-skills}/skills/productivity/handoff";
      repo = "mattpocock/skills";
    }
    {
      name = "improve-codebase-architecture";
      path = "${inputs.mattpocock-skills}/skills/engineering/improve-codebase-architecture";
      repo = "mattpocock/skills";
    }
    {
      name = "prototype";
      path = "${inputs.mattpocock-skills}/skills/engineering/prototype";
      repo = "mattpocock/skills";
    }
    {
      name = "setup-matt-pocock-skills";
      path = "${inputs.mattpocock-skills}/skills/engineering/setup-matt-pocock-skills";
      repo = "mattpocock/skills";
    }
    {
      name = "tdd";
      path = "${inputs.mattpocock-skills}/skills/engineering/tdd";
      repo = "mattpocock/skills";
    }
    {
      name = "to-issues";
      path = "${inputs.mattpocock-skills}/skills/engineering/to-issues";
      repo = "mattpocock/skills";
    }
    {
      name = "to-prd";
      path = "${inputs.mattpocock-skills}/skills/engineering/to-prd";
      repo = "mattpocock/skills";
    }
    {
      name = "triage";
      path = "${inputs.mattpocock-skills}/skills/engineering/triage";
      repo = "mattpocock/skills";
    }
    {
      name = "write-a-skill";
      path = "${inputs.mattpocock-skills}/skills/productivity/write-a-skill";
      repo = "mattpocock/skills";
    }
    {
      name = "zoom-out";
      path = "${inputs.mattpocock-skills}/skills/engineering/zoom-out";
      repo = "mattpocock/skills";
    }
  ];

  claude = [ ];
  codex = [ ];
  opencode = [ ];
  pi = [ ];
}
