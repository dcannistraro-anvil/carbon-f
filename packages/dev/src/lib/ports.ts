import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import net from "node:net";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { generateJwtCreds, type JwtCreds } from "./jwt.js";

export const PORT_NAMES = [
  "PORT_DB",
  "PORT_API",
  "PORT_STUDIO",
  "PORT_INBUCKET",
  "PORT_INNGEST"
] as const;

type PortName = (typeof PORT_NAMES)[number];
export type PortMap = Record<PortName, number>;

const REDIS_DB_MAX = 16;
export const SHARED_REDIS_PORT = 6379;

const REGISTRY_PATH = join(homedir(), ".carbon", "dev-ports.json");

type RegistryEntry = {
  worktreeRoot: string;
  ports: PortMap;
  redisDb: number;
  jwt: JwtCreds;
};
type Registry = Record<string, RegistryEntry>;

function readRegistry(): Registry {
  if (!existsSync(REGISTRY_PATH)) return {};
  try {
    return JSON.parse(readFileSync(REGISTRY_PATH, "utf8"));
  } catch {
    return {};
  }
}

function writeRegistry(registry: Registry) {
  mkdirSync(dirname(REGISTRY_PATH), { recursive: true });
  writeFileSync(REGISTRY_PATH, JSON.stringify(registry, null, 2));
}

export async function resolveSlot(
  slug: string,
  worktreeRoot: string
): Promise<{ ports: PortMap; redisDb: number; jwt: JwtCreds }> {
  const registry = readRegistry();
  const existing = registry[slug];
  if (
    existing &&
    existing.worktreeRoot === worktreeRoot &&
    typeof existing.redisDb === "number" &&
    existing.jwt?.secret
  ) {
    return {
      ports: existing.ports,
      redisDb: existing.redisDb,
      jwt: existing.jwt
    };
  }

  const claimedPorts = new Set<number>();
  const claimedDbs = new Set<number>();
  for (const [s, entry] of Object.entries(registry)) {
    if (s === slug) continue;
    for (const p of Object.values(entry.ports)) claimedPorts.add(p);
    if (typeof entry.redisDb === "number") claimedDbs.add(entry.redisDb);
  }

  const ports =
    existing?.ports && existing.worktreeRoot === worktreeRoot
      ? existing.ports
      : await pickPorts(claimedPorts);

  const redisDb =
    typeof existing?.redisDb === "number"
      ? existing.redisDb
      : pickRedisDb(claimedDbs);

  // JWT creds tied to data signed/stored in postgres — rotating invalidates
  // existing sessions, so reuse when present.
  const jwt = existing?.jwt?.secret ? existing.jwt : generateJwtCreds();

  registry[slug] = { worktreeRoot, ports, redisDb, jwt };
  writeRegistry(registry);
  return { ports, redisDb, jwt };
}

export function getSlot(slug: string): RegistryEntry | null {
  return readRegistry()[slug] ?? null;
}

export function listSlugs(): Registry {
  return readRegistry();
}

export function removeSlot(slug: string) {
  const registry = readRegistry();
  if (!(slug in registry)) return;
  delete registry[slug];
  writeRegistry(registry);
}

function pickRedisDb(taken: Set<number>): number {
  for (let i = 0; i < REDIS_DB_MAX; i++) {
    if (!taken.has(i)) return i;
  }
  throw new Error(
    `Redis DB pool exhausted (max ${REDIS_DB_MAX}). Free a slot via \`crbn remove\`.`
  );
}

async function pickPorts(claimed: Set<number>): Promise<PortMap> {
  const ports = {} as PortMap;
  for (const name of PORT_NAMES) {
    ports[name] = await pickFreePort(claimed);
  }
  return ports;
}

async function pickFreePort(taken: Set<number>): Promise<number> {
  // OS-assigned ephemeral via listen(0); retry on collision with other
  // worktrees' claimed-set.
  for (let attempt = 0; attempt < 100; attempt++) {
    const port = await new Promise<number>((resolve, reject) => {
      const server = net.createServer();
      server.unref();
      server.on("error", reject);
      server.listen(0, "127.0.0.1", () => {
        const addr = server.address();
        if (typeof addr === "object" && addr) {
          const p = addr.port;
          server.close(() => resolve(p));
        } else {
          server.close();
          reject(new Error("could not determine port"));
        }
      });
    });
    if (!taken.has(port)) {
      taken.add(port);
      return port;
    }
  }
  throw new Error("Failed to allocate a free port after 100 attempts");
}
