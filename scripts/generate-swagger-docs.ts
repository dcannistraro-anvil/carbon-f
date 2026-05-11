import { writeFileSync } from "node:fs";
import * as dotenv from "dotenv";

dotenv.config({ path: ".env" });
dotenv.config({ path: ".env.local", override: true });

const studioPort = process.env.PORT_STUDIO;
if (!studioPort) {
  console.error(
    "PORT_STUDIO not set (expected in .env.local). Run `pnpm dev:up` first."
  );
  process.exit(1);
}

const url = `http://localhost:${studioPort}/api/platform/projects/default/api/rest`;

(async () => {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`HTTP error! status: ${response.status}`);
  }

  const data = await response.json();

  writeFileSync(
    "packages/database/src/swagger-docs-schema.ts",
    `export default ${JSON.stringify(data, null, 2)}`
  );
})();
