// Compatibility surface for existing Oracle/Worker consumers. The reusable
// implementation lives in shared/subagent-progress.ts.
export {
  MAX_TOOL_CALLS_TO_KEEP,
  formatSubagentToolCall,
  formatToolCall,
  shorten,
  type SubagentStatus,
  type SubagentToolCall,
} from "../shared/subagent-progress.ts";
import type {
  SubagentDetails,
  SubagentRunDetails,
  SubagentToolCall,
} from "../shared/subagent-progress.ts";

export type DelegateStatus = SubagentDetails["status"];
export type DelegateToolCall = SubagentToolCall;
export type DelegateRunDetails = Omit<SubagentRunDetails, "maxTurns"> & {
  maxTurns: number;
};

/** Stable result details emitted by the Oracle and Worker tools. */
export type DelegateDetails = Omit<
  SubagentDetails<"oracle" | "worker", "high" | "xhigh">,
  "agent" | "taskLabel" | "run" | "metadata"
> & {
  delegate: "oracle" | "worker";
  run: DelegateRunDetails;
};
