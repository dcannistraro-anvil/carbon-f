import Table from "cli-table3";
import pc from "picocolors";
import { PORT_NAMES, type PortMap, SHARED_REDIS_PORT } from "../lib/ports.js";
import type { Container } from "../services/compose.js";

/** Common cli-table3 style: gray border, no inter-row separators. */
const BASE_STYLE = {
  style: { head: [], border: ["gray"] as string[] },
  chars: {
    mid: "",
    "left-mid": "",
    "mid-mid": "",
    "right-mid": ""
  }
};

/** Per-worktree port + redis-db assignment table. */
export function portsTable(
  ports: PortMap,
  redisDb: number | undefined
): string {
  const t = new Table({
    head: [pc.bold("Service"), pc.bold("Port")],
    ...BASE_STYLE
  });
  for (const n of PORT_NAMES) {
    t.push([
      pc.cyan(n.replace("PORT_", "").toLowerCase()),
      pc.bold(String(ports[n]))
    ]);
  }
  t.push([
    pc.cyan("redis (shared)"),
    pc.bold(String(SHARED_REDIS_PORT)) +
      pc.dim(typeof redisDb === "number" ? ` /db ${redisDb}` : " /db ?")
  ]);
  return t.toString();
}

/** Compose-stack health table for `dev status`. */
export function servicesTable(containers: Container[]): string {
  const sorted = [...containers].sort((a, b) =>
    a.Service.localeCompare(b.Service)
  );
  const t = new Table({
    head: [pc.bold("Service"), pc.bold("Status"), pc.bold("Ports")],
    ...BASE_STYLE
  });
  for (const c of sorted) {
    t.push([pc.cyan(c.Service), colorState(c.State, c.Health), formatPorts(c)]);
  }
  return t.toString();
}

/** Worktree list table for `dev list`. */
export function worktreesTable(
  rows: {
    path: string;
    branch: string | null;
    current: boolean;
    slug: string | null;
    dockerState: string | null;
  }[]
): string {
  const t = new Table({
    head: [pc.bold("Worktree"), pc.bold("Branch"), pc.bold("Stack")],
    ...BASE_STYLE
  });
  for (const r of rows) {
    const project = r.slug ? `carbon-${r.slug}` : "—";
    const stack = !r.slug
      ? pc.gray("not initialized")
      : r.dockerState === "running"
        ? pc.green(`● up · ${project}`)
        : r.dockerState
          ? pc.yellow(`${r.dockerState} · ${project}`)
          : pc.dim(`registered · ${project}`);
    t.push([
      r.current ? pc.bold(pc.cyan(r.path)) : r.path,
      r.branch ? pc.cyan(r.branch) : pc.dim("(detached)"),
      stack
    ]);
  }
  return t.toString();
}

function colorState(state: string, health?: string): string {
  const s = state.toLowerCase();
  if (s === "running" && health === "unhealthy")
    return pc.yellow("◑ unhealthy");
  if (s === "running" && health === "starting") return pc.yellow("◐ starting");
  if (s === "running") return pc.green("● running");
  if (s === "restarting") return pc.yellow("◌ restarting");
  if (s === "exited") return pc.red("✗ exited");
  if (s === "created") return pc.gray("○ created");
  return pc.dim(state);
}

function formatPorts(c: Container): string {
  if (!c.Publishers || c.Publishers.length === 0) return pc.dim("—");
  const seen = new Set<string>();
  const out: string[] = [];
  for (const p of c.Publishers) {
    if (!p.PublishedPort) continue;
    const key = `${p.PublishedPort}:${p.TargetPort}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(
      `${pc.cyan(String(p.PublishedPort))}${pc.dim("→" + p.TargetPort)}`
    );
  }
  return out.length ? out.join(" ") : pc.dim("—");
}
