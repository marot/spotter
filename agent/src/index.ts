import { query, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import { buildSystemPrompt, type CommitInput } from "./prompt.js";
import { allTools, setCommitHash } from "./tools.js";
import * as dolt from "./dolt.js";

interface ToolCallRecord {
  name: string;
  ms: number;
}

interface AgentOutput {
  ok: boolean;
  tool_calls: ToolCallRecord[];
  changed_entities_count: number;
  error?: string;
}

async function readStdin(): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk as Buffer);
  }
  return Buffer.concat(chunks).toString("utf-8");
}

async function main(): Promise<void> {
  const traceparent = process.env.TRACEPARENT;
  if (traceparent) {
    process.stderr.write(`[spec-agent] traceparent=${traceparent}\n`);
  }

  let input: CommitInput;
  try {
    const raw = await readStdin();
    input = JSON.parse(raw) as CommitInput;
  } catch (err) {
    const output: AgentOutput = {
      ok: false,
      tool_calls: [],
      changed_entities_count: 0,
      error: `Failed to parse stdin: ${err}`,
    };
    process.stdout.write(JSON.stringify(output));
    process.exit(1);
  }

  setCommitHash(input.commit_hash);

  const server = createSdkMcpServer({
    name: "spec-tools",
    version: "1.0.0",
    tools: allTools,
  });

  const toolNames = [
    "domains_list",
    "domains_create",
    "domains_update",
    "features_search",
    "features_create",
    "features_update",
    "features_delete",
    "requirements_search",
    "requirements_create",
    "requirements_update",
    "requirements_delete",
  ];

  const allowedTools = toolNames.map((t) => `mcp__spec-tools__${t}`);
  const systemPrompt = buildSystemPrompt(input);

  const toolCalls: ToolCallRecord[] = [];
  let changedCount = 0;

  try {
    for await (const message of query({
      prompt: systemPrompt,
      options: {
        mcpServers: { "spec-tools": server },
        allowedTools,
        maxTurns: 15,
      },
    })) {
      if (
        message.type === "assistant" &&
        "message" in message &&
        message.message &&
        typeof message.message === "object" &&
        "content" in message.message
      ) {
        const content = (message.message as { content: unknown[] }).content;
        if (Array.isArray(content)) {
          for (const block of content) {
            if (
              typeof block === "object" &&
              block !== null &&
              "type" in block &&
              (block as { type: string }).type === "tool_use"
            ) {
              const name = (block as unknown as { name: string }).name;
              const isWrite =
                name.includes("create") ||
                name.includes("update") ||
                name.includes("delete");
              if (isWrite) changedCount++;
              toolCalls.push({ name, ms: 0 });
            }
          }
        }
      }
    }

    const output: AgentOutput = {
      ok: true,
      tool_calls: toolCalls,
      changed_entities_count: changedCount,
    };
    process.stdout.write(JSON.stringify(output));
  } catch (err) {
    const output: AgentOutput = {
      ok: false,
      tool_calls: toolCalls,
      changed_entities_count: changedCount,
      error: String(err),
    };
    process.stdout.write(JSON.stringify(output));
    process.exit(1);
  } finally {
    await dolt.shutdown();
  }
}

main();
