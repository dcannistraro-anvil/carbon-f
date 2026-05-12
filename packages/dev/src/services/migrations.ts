import net from "node:net";
import { join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";
import { execa } from "execa";

// Block until each tcp:<port> accepts on 127.0.0.1. `onProgress` fires once
// per port as it opens — caller streams these into a spinner subtitle so a
// stuck service (e.g. inngest pulling its container) is visible instead of a
// 60s silent hang.
export async function waitForTcp(
  targets: string[],
  opts: { onProgress?: (line: string) => void } = {}
) {
  const ports = targets.map((t) => {
    const m = t.match(/^tcp:(\d+)$/);
    if (!m)
      throw new Error(`waitForTcp: bad target "${t}" (expected tcp:<port>)`);
    return Number(m[1]);
  });
  const total = ports.length;
  let opened = 0;
  await Promise.all(
    ports.map(async (p) => {
      await waitForPort(p, 60_000);
      opened += 1;
      opts.onProgress?.(`tcp:${p} open (${opened}/${total})`);
    })
  );
}

async function waitForPort(
  port: number,
  timeoutMs: number,
  host = "127.0.0.1"
) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const ok = await tryConnect(host, port);
    if (ok) return;
    await sleep(500);
  }
  throw new Error(`timed out waiting for tcp:${port} after ${timeoutMs}ms`);
}

function tryConnect(host: string, port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = net.connect({ host, port });
    const done = (ok: boolean) => {
      socket.removeAllListeners();
      socket.destroy();
      resolve(ok);
    };
    socket.once("connect", () => done(true));
    socket.once("error", () => done(false));
    socket.setTimeout(2000, () => done(false));
  });
}

// Block until postgres accepts queries, then until supabase storage-api
// bootstraps `storage.buckets`. Postgres opens its TCP port well before init
// scripts finish — querying `SELECT 1` is the real readiness signal. Storage
// only starts its bootstrap once postgres is healthy, so both gates share one
// budget. `onTimeout` runs before the throw so callers can surface container
// state / logs without leaking compose-project knowledge into this module.
export async function waitForStorageTables(
  port: number,
  opts: {
    onTimeout?: () => Promise<void>;
    onProgress?: (line: string) => void;
  } = {}
) {
  const url = `postgresql://postgres:postgres@localhost:${port}/postgres`;
  const env = { ...process.env, PGSSLMODE: "disable" };
  const deadline = Date.now() + 180_000;
  const start = Date.now();
  const elapsed = () => Math.floor((Date.now() - start) / 1000);

  opts.onProgress?.("waiting for postgres to accept queries");
  while (Date.now() < deadline) {
    const r = await execa("psql", [url, "-tAc", "SELECT 1"], {
      env,
      reject: false
    });
    if (r.exitCode === 0 && r.stdout?.trim() === "1") {
      opts.onProgress?.(`postgres ready (${elapsed()}s)`);
      break;
    }
    await sleep(1000);
  }

  opts.onProgress?.("waiting for storage-api to create storage.buckets");
  while (Date.now() < deadline) {
    const r = await execa(
      "psql",
      [url, "-tAc", "SELECT to_regclass('storage.buckets')"],
      { env, reject: false }
    );
    if (r.exitCode === 0 && r.stdout?.trim() === "storage.buckets") {
      opts.onProgress?.(`storage.buckets ready (${elapsed()}s)`);
      return;
    }
    await sleep(1000);
  }

  if (opts.onTimeout) {
    try {
      await opts.onTimeout();
    } catch {
      // diagnostics are best-effort; original error below is what matters
    }
  }
  throw new Error("storage.buckets did not appear within 180s");
}

// --include-all: supabase bootstrap inserts a sentinel into schema_migrations
// that makes earlier-timestamp migrations look "out of order" without it.
// Returns `applied: true` when at least one migration ran — callers gate
// type/swagger regen on this so a re-run against an up-to-date DB stays cheap.
export async function applyMigrations(
  root: string,
  dbPort: number
): Promise<{ applied: boolean }> {
  const args = [
    "migration",
    "up",
    "--include-all",
    "--db-url",
    `postgresql://postgres:postgres@localhost:${dbPort}/postgres`
  ];
  const cwd = join(root, "packages/database");
  const r = await execa("supabase", args, {
    cwd,
    reject: false,
    preferLocal: true
  });
  if (r.exitCode !== 0) {
    process.stderr.write(r.stderr?.toString() ?? "");
    process.stdout.write(r.stdout?.toString() ?? "");
    throw new Error(`supabase ${args.join(" ")} failed (exit ${r.exitCode})`);
  }
  // supabase prints "Applying migration <ts>_<name>.sql..." per applied
  // migration; absent that, the schema was already current.
  const applied = /Applying migration/i.test(r.stdout ?? "");
  return { applied };
}
