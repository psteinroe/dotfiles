{ inputs }:
{
  # Sources stay pinned in flake.lock; updates are deliberate.
  shared = [
    {
      name = "writing-for-agents";
      path = "${inputs.mattpocock-skills}/skills/productivity/writing-for-agents";
      repo = "mattpocock/skills";
    }
  ];

  pi = [
    {
      name = "gh-stack";
      path = "${inputs.gh-stack-skills}/skills/gh-stack";
      repo = "github/gh-stack";
    }
  ];
}
