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
      path = "${inputs.mattpocock-skills}/grill-me";
      repo = "mattpocock/skills";
    }
  ];

  claude = [ ];
  codex = [ ];
  opencode = [ ];
  pi = [ ];
}
