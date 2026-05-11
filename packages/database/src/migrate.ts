import { spawnSync } from "node:child_process";
import net from "node:net";
import * as dotenv from "dotenv";

dotenv.config({ path: ".env" });
dotenv.config({ path: ".env.local", override: true });

function reachable(host: string, port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const s = net.connect({ host, port });
    const done = (ok: boolean) => {
      s.removeAllListeners();
      s.destroy();
      resolve(ok);
    };
    s.once("connect", () => done(true));
    s.once("error", () => done(false));
    s.setTimeout(1500, () => done(false));
  });
}

async function main() {
  const dbUrl = process.env.SUPABASE_DB_URL;
  const extraArgs = process.argv.slice(2);

  // When SUPABASE_DB_URL points at a local stack, pre-flight a TCP check so we
  // surface "stack isn't running" instead of supabase's misleading "Network
  // Restrictions" cloud-dashboard error.
  if (dbUrl) {
    const m = dbUrl.match(/@([^:/]+):(\d+)\//);
    if (
      m &&
      (m[1] === "localhost" || m[1] === "127.0.0.1") &&
      !(await reachable(m[1], Number(m[2])))
    ) {
      console.error(
        `Local DB at ${m[1]}:${m[2]} is not reachable.\nStart the dev stack first: \`pnpm dev\` (or \`crbn up\`).`
      );
      process.exit(1);
    }
  }

  // When SUPABASE_DB_URL is set (dev stack via crbn up, or explicit override),
  // target it directly. Otherwise fall back to `supabase migration up` against
  // the CLI's linked project — preserves pre-PR behavior for operators who run
  // `supabase link` and then `pnpm db:migrate`.
  const args = dbUrl
    ? ["migration", "up", "--db-url", dbUrl, ...extraArgs]
    : ["migration", "up", ...extraArgs];

  const r = spawnSync("supabase", args, { stdio: "inherit" });
  process.exit(r.status ?? 1);
}

main();
