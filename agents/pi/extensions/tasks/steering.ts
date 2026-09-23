import type { AgentSession } from "@earendil-works/pi-coding-agent";

/** Live sessions only; task ownership and cancellation remain in TaskRegistry. */
export class TaskSteering {
  private sessions = new Map<string, Pick<AgentSession, "isStreaming" | "steer">>();

  register(id: string, session: Pick<AgentSession, "isStreaming" | "steer">): () => void {
    this.sessions.set(id, session);
    return () => {
      if (this.sessions.get(id) === session) this.sessions.delete(id);
    };
  }

  async steer(id: string, message: string): Promise<void> {
    const session = this.sessions.get(id);
    if (!session?.isStreaming) {
      throw new Error(`${id} is not currently processing a prompt; retry while it is running.`);
    }
    await session.steer(message);
  }

  clear(): void {
    this.sessions.clear();
  }
}
