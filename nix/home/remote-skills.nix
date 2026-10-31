{ inputs }:
let
  ghStack = {
    name = "gh-stack";
    path = "${inputs.gh-stack-skills}/skills/gh-stack";
    repo = "github/gh-stack";
  };
in
{
  # Sources stay pinned in flake.lock; updates are deliberate.
  shared = [
    {
      name = "writing-for-agents";
      path = "${inputs.mattpocock-skills}/skills/productivity/writing-for-agents";
      repo = "mattpocock/skills";
    }
  ];

  pi = [ ghStack ];

  # Claude Code and Codex, which run under T3, get these next to tstack's skills
  clients = [ ghStack ];
}
