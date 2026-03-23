import { IAgent, ITool } from "./type";

export class CodeAgent implements IAgent {
  name = "code";
  tools: Map<string, ITool>;

  constructor() {
    this.tools = new Map<string, ITool>();
  }

  shouldHandle(req: any, config: any): boolean {
    // Note: Model switching for coding tasks is now handled natively in core/utils/router.ts
    // This agent is reserved for future custom tool logic or prompt injections specifically for coding.
    return false;
  }

  reqHandler(req: any, config: any) {
    // Optional: Add coding-specific system prompt enhancements here
  }
}

export const codeAgent = new CodeAgent();
