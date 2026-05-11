import net from "node:net";
import { join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";
import { execa } from "execa";

// Block until each tcp:<port> accepts on 127.0.0.1.
export async function waitForTcp(targets: string[]) {
  const ports = targets.map((t) => {
    const m = t.match(/^tcp:(\d+)$/);
    if (!m)
      throw new Error(`waitForTcp: bad target "${t}" (expected tcp:<port>)`);
    return Number(m[1]);
  });
  await Promise.all(ports.map((p) => waitForPort(p, 60_000)));
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

// Block until supabase storage-api bootstraps `storage.buckets`.
export async function waitForStorageTables(port: number) {
  const url = `postgresql://postgres:postgres@localhost:${port}/postgres`;
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    const r = await execa(
      "psql",
      [url, "-tAc", "SELECT to_regclass('storage.buckets')"],
      { env: { ...process.env, PGSSLMODE: "disable" }, reject: false }
    );
    if (r.exitCode === 0 && r.stdout?.trim() === "storage.buckets") return;
    await sleep(1000);
  }
  throw new Error("storage.buckets did not appear within 60s");
}

// --include-all: supabase bootstrap inserts a sentinel into schema_migrations
// that makes earlier-timestamp migrations look "out of order" without it.
export async function applyMigrations(root: string, dbPort: number) {
  await execStrict(
    "supabase",
    [
      "migration",
      "up",
      "--include-all",
      "--db-url",
      `postgresql://postgres:postgres@localhost:${dbPort}/postgres`
    ],
    join(root, "packages/database")
  );
}

async function execStrict(cmd: string, args: string[], cwd: string) {
  const r = await execa(cmd, args, { cwd, reject: false, preferLocal: true });
  if (r.exitCode !== 0) {
    process.stderr.write(r.stderr?.toString() ?? "");
    process.stdout.write(r.stdout?.toString() ?? "");
    throw new Error(`${cmd} ${args.join(" ")} failed (exit ${r.exitCode})`);
  }
}
