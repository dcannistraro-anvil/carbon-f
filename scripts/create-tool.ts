import { existsSync, writeFileSync } from "fs";
import { join } from "path";

const toolName = process.argv[2];

if (!toolName) {
  console.error("Error: Tool name is required");
  console.log("Usage: pnpm run tool:new <toolName>");
  console.log("Example: pnpm run tool:new getPart");
  process.exit(1);
}

// Convert toolName to kebab-case for file name
const fileName = toolName.replace(/([a-z])([A-Z])/g, "$1-$2").toLowerCase();

const TOOLS_DIR = join(
  process.cwd(),
  "apps",
  "erp",
  "app",
  "routes",
  "api+",
  "ai+",
  "chat+",
  "tools"
);

if (!existsSync(TOOLS_DIR)) {
  console.error(`Error: Tools directory not found at ${TOOLS_DIR}`);
  process.exit(1);
}

const toolFilePath = join(TOOLS_DIR, `${fileName}.ts`);

if (existsSync(toolFilePath)) {
  console.error(`Error: Tool file already exists at ${toolFilePath}`);
  process.exit(1);
}

const toolTemplate = `import { tool } from "ai";
import { LuSearch } from "react-icons/lu";
import { z } from "zod";
import type { ToolConfig } from "../agents/shared/tools";
import type { ChatContext } from "../agents/shared/context";

export const config: ToolConfig = {
  name: "${toolName}",
  icon: LuSearch,
  displayText: "Processing ${toolName}",
  message: "Processing ${toolName.toLowerCase()}...",
};

export const ${toolName}Schema = z.object({
  // Add your schema properties here
});

export const ${toolName}Tool = tool({
  description: "Description of what this tool does",
  inputSchema: ${toolName}Schema,
  execute: async function (args, executionOptions) {
    const context = executionOptions.experimental_context as ChatContext;

    // TODO: Implement tool logic here

    return {
      message: "Hello from ${toolName}!",
    };
  },
});
`;

try {
  writeFileSync(toolFilePath, toolTemplate, "utf-8");
  console.log(`✅ Successfully created tool at ${toolFilePath}`);
  console.log(`\nNext steps:`);
  console.log(`1. Edit ${toolFilePath} to implement your tool logic`);
  console.log(`2. Update the schema in ${toolName}Schema`);
  console.log(`3. Update the description and execute function`);
  console.log(`4. Change the icon if needed (from react-icons/lu)`);
} catch (error) {
  console.error(`Failed to create tool file:`, error);
  process.exit(1);
}
