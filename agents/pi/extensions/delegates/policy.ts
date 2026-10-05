export type DelegateName = "oracle" | "worker";

export interface DelegatePolicy {
  readonly model: string;
  readonly thinking: "high" | "xhigh";
  readonly maxTurns: number;
  readonly tools: readonly string[];
}

export const DELEGATE_POLICIES: Record<DelegateName, DelegatePolicy> = {
  oracle: {
    model: "openai-codex/gpt-6-astra",
    thinking: "xhigh",
    maxTurns: 10,
    tools: ["read", "grep", "find", "ls", "git_diff"],
  },
  worker: {
    model: "claude-bridge/claude-opus-5-5",
    thinking: "high",
    maxTurns: 50,
    tools: ["read", "bash", "edit", "write", "grep", "find", "ls"],
  },
};

export type GitDiffTarget = "working" | "staged" | "head";

export function gitDiffArgs(target: GitDiffTarget): string[] {
  switch (target) {
    case "working":
      return ["diff", "--no-ext-diff", "--"];
    case "staged":
      return ["diff", "--cached", "--no-ext-diff", "--"];
    case "head":
      return ["show", "--format=fuller", "--no-ext-diff", "HEAD", "--"];
  }
}

export function truncateDelegateOutput(text: string, maxChars = 24_000) {
  if (text.length <= maxChars) return { text, truncated: false };
  return {
    text: `${text.slice(0, maxChars)}\n\n[delegate output truncated]`,
    truncated: true,
  };
}
