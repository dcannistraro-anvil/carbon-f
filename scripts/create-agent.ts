import { existsSync, writeFileSync } from "fs";
import { join } from "path";

const agentName = process.argv[2];

if (!agentName) {
  console.error("Error: Agent name is required");
  console.log("Usage: pnpm run agent:new <agentName>");
  console.log("Example: pnpm run agent:new inventory");
  process.exit(1);
}

// Convert agentName to kebab-case for file name
const fileName = agentName.replace(/([a-z])([A-Z])/g, "$1-$2").toLowerCase();

const AGENTS_DIR = join(
  process.cwd(),
  "apps",
  "erp",
  "app",
  "routes",
  "api+",
  "ai+",
  "chat+",
  "agents"
);

if (!existsSync(AGENTS_DIR)) {
  console.error(`Error: Agents directory not found at ${AGENTS_DIR}`);
  process.exit(1);
}

const agentFilePath = join(AGENTS_DIR, `${fileName}-agent.ts`);

if (existsSync(agentFilePath)) {
  console.error(`Error: Agent file already exists at ${agentFilePath}`);
  process.exit(1);
}

// Convert to PascalCase for display name
const displayName =
  agentName.charAt(0).toUpperCase() +
  agentName.slice(1).replace(/([A-Z])/g, " $1");

const agentTemplate = `import { openai } from "@ai-sdk/openai";
import { createAgent } from "./shared/agent";
import { COMMON_AGENT_RULES, formatContextForLLM } from "./shared/prompts";
import type { AgentConfig } from "./shared/tools";

export const config: AgentConfig = {
  name: "${agentName}",
  displayName: "${displayName} Agent",
  description: "Description of what this agent does",
  executingMessage: "Calling the ${agentName} agent...",
};

export const ${agentName}Agent = createAgent({
  name: "${agentName}",
  model: openai("gpt-4o"),
  temperature: 0.5,
  instructions: (ctx) => \`You are a ${agentName} specialist for \${ctx.companyName}.

<background-data>
\${formatContextForLLM(ctx)}
</background-data>

\${COMMON_AGENT_RULES}

<capabilities>
- Add your agent capabilities here
</capabilities>\`,
  tools: {
    // Add your tools here
    // exampleTool: exampleToolTool,
  },
  handoffs: [],
  maxTurns: 10,
});
`;

try {
  writeFileSync(agentFilePath, agentTemplate, "utf-8");
  console.log(`✅ Successfully created agent at ${agentFilePath}`);
  console.log(`\nNext steps:`);
  console.log(`1. Edit ${agentFilePath} to implement your agent logic`);
  console.log(`2. Add tools to the tools object`);
  console.log(`3. Update the instructions and capabilities`);
  console.log(`4. Configure handoffs to other agents if needed`);
  console.log(
    `5. Add the agent to the AgentStatus type in app/components/Chat/lib/types.ts`
  );
  console.log(
    `6. Import and add the agent to handoffs in orchestration-agent.ts if needed`
  );
} catch (error) {
  console.error(`Failed to create agent file:`, error);
  process.exit(1);
}
