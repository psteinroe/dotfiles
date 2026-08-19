export type DelegateName = "oracle" | "worker";

export interface DelegatePolicy {
  readonly model: string;
  readonly thinking: "high" | "xhigh";
  readonly maxTurns: number;
  readonly tools: readonly string[];
}

export class DelegateCapacity {
  private activeCount = 0;
  private readonly maximum: number;

  constructor(maximum: number) {
    this.maximum = maximum;
  }

  acquire(): () => void {
    if (this.activeCount >= this.maximum) {
      throw new Error(
        `At most ${this.maximum} delegates can run concurrently. Wait for one to finish.`,
      );
    }
    this.activeCount++;

    let active = true;
    return () => {
      if (!active) return;
      active = false;
      this.activeCount--;
    };
  }
}

export const DELEGATE_CONCURRENCY: Record<DelegateName, number> = {
  oracle: 1,
  worker: 4,
};

export const DELEGATE_POLICIES: Record<DelegateName, DelegatePolicy> = {
  oracle: {
    model: "gpt-5.6-sol",
    thinking: "xhigh",
    maxTurns: 10,
    tools: ["read", "grep", "find", "ls", "git_diff"],
  },
  worker: {
    model: "gpt-5.6-luna",
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
