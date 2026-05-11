import { log } from "@clack/prompts";
import { execa } from "execa";
import { COMPOSE_DEV_FILE, COMPOSE_SHARED_FILE } from "../constants.js";
import { SHARED_REDIS_PORT } from "../lib/ports.js";
import { projectName } from "../lib/slug.js";

export async function bootStack(root: string, slug: string) {
  await execStrict(
    "docker",
    [
      "compose",
      "-f",
      COMPOSE_DEV_FILE,
      "-p",
      projectName(slug),
      "--env-file",
      ".env.local",
      "up",
      "-d"
    ],
    root
  );
}

export async function stopStack(
  root: string,
  slug: string,
  withVolumes: boolean
) {
  const args = [
    "compose",
    "-f",
    COMPOSE_DEV_FILE,
    "-p",
    projectName(slug),
    "down"
  ];
  if (withVolumes) args.push("-v");
  await execa("docker", args, { cwd: root, stdio: "ignore", reject: false });
}

// One redis per host; recover from stale `carbon-redis` leftovers.
export async function bootSharedRedis(root: string) {
  const args = ["compose", "-f", COMPOSE_SHARED_FILE, "up", "-d", "redis"];
  let r = await execa("docker", args, { cwd: root, reject: false });
  if (r.exitCode !== 0 && /already in use/i.test(r.stderr ?? "")) {
    await execa("docker", ["rm", "-f", "carbon-redis"], {
      reject: false,
      stdio: "ignore"
    });
    r = await execa("docker", args, { cwd: root, reject: false });
  }
  if (r.exitCode !== 0) {
    process.stderr.write(r.stderr ?? "");
    throw new Error(`shared redis up failed (exit ${r.exitCode})`);
  }
}

export async function destroyProjectVolumes(cwd: string, project: string) {
  await execa(
    "docker",
    ["compose", "-f", COMPOSE_DEV_FILE, "-p", project, "down", "-v"],
    { cwd, stdio: "ignore", reject: false }
  );
}

export async function listContainers(
  root: string,
  slug: string
): Promise<Container[]> {
  const r = await execa(
    "docker",
    [
      "compose",
      "-f",
      COMPOSE_DEV_FILE,
      "-p",
      projectName(slug),
      "ps",
      "-a",
      "--format",
      "json"
    ],
    { cwd: root, reject: false }
  );
  if (r.exitCode !== 0 || !r.stdout?.trim()) return [];
  return r.stdout
    .split("\n")
    .filter(Boolean)
    .map((l) => JSON.parse(l) as Container);
}

export async function dockerProjectStates(): Promise<Map<string, string>> {
  const out = new Map<string, string>();
  const r = await execa(
    "docker",
    [
      "ps",
      "-a",
      "--format",
      '{{.Label "com.docker.compose.project"}}\t{{.State}}'
    ],
    { reject: false }
  );
  for (const line of (r.stdout ?? "").split("\n")) {
    const [project, state] = line.split("\t");
    if (!project || !state) continue;
    if (state === "running") out.set(project, "running");
    else if (!out.has(project)) out.set(project, state);
  }
  return out;
}

export type Container = {
  Service: string;
  Name: string;
  State: string;
  Status: string;
  Health?: string;
  Publishers?: { PublishedPort: number; TargetPort: number }[] | null;
};

// Wipe one logical DB on shared redis. Host redis-cli, fallback docker exec.
export async function flushDb(db: number) {
  let r = await execa(
    "redis-cli",
    [
      "-h",
      "localhost",
      "-p",
      String(SHARED_REDIS_PORT),
      "-n",
      String(db),
      "FLUSHDB"
    ],
    { reject: false, stdio: "ignore" }
  );
  if (r.exitCode !== 0) {
    r = await execa(
      "docker",
      ["exec", "carbon-redis", "redis-cli", "-n", String(db), "FLUSHDB"],
      { reject: false, stdio: "ignore" }
    );
  }
  if (r.exitCode !== 0) {
    log.warn(`redis flush of db ${db} failed (skipped)`);
  }
}

async function execStrict(cmd: string, args: string[], cwd: string) {
  const r = await execa(cmd, args, { cwd, reject: false, preferLocal: true });
  if (r.exitCode !== 0) {
    process.stderr.write(r.stderr?.toString() ?? "");
    process.stdout.write(r.stdout?.toString() ?? "");
    throw new Error(`${cmd} ${args.join(" ")} failed (exit ${r.exitCode})`);
  }
}
