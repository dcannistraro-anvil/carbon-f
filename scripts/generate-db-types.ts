import { closeSync, copyFileSync, openSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join } from "node:path";
import * as dotenv from "dotenv";

dotenv.config({ path: ".env" });
dotenv.config({ path: ".env.local", override: true });

const dbUrl = process.env.SUPABASE_DB_URL;
if (!dbUrl) {
  console.error(
    "SUPABASE_DB_URL not set (expected in .env or .env.local). Run `pnpm dev:up` first."
  );
  process.exit(1);
}

if (!/(localhost|127\.0\.0\.1)/.test(dbUrl)) {
  console.error(
    `Refusing to generate types against non-local DB: ${dbUrl.replace(/:[^:@/]+@/, ":***@")}`
  );
  process.exit(1);
}

const typesPath = join("packages", "database", "src", "types.ts");
const fnTypesPath = join(
  "packages",
  "database",
  "supabase",
  "functions",
  "lib",
  "types.ts"
);

// Pipe supabase stdout directly to the types file to avoid spawnSync's 1MB
// default buffer cap (generated types are ~MBs).
const out = openSync(typesPath, "w");
const r = spawnSync(
  "supabase",
  [
    "gen",
    "types",
    "typescript",
    "--db-url",
    dbUrl,
    "--schema",
    "public",
    "--schema",
    "storage",
    "--schema",
    "graphql_public"
  ],
  { stdio: ["ignore", out, "inherit"] }
);
closeSync(out);

if (r.status !== 0) {
  console.error(`supabase gen types failed (exit ${r.status})`);
  process.exit(r.status ?? 1);
}

copyFileSync(typesPath, fnTypesPath);
console.log(`wrote ${typesPath}\nwrote ${fnTypesPath}`);
