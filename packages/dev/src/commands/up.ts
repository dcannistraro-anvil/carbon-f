import { join } from "node:path";
import { box, intro, log, outro, tasks } from "@clack/prompts";
import { config as loadDotenv } from "dotenv";
import { execa } from "execa";
import { currentBranch, isLinkedWorktree } from "../lib/git.js";
import { resolveSlot, SHARED_REDIS_PORT } from "../lib/ports.js";
import {
  renderEnv,
  syncAppPortlessConfigs,
  writeEnv
} from "../lib/render-env.js";
import {
  ensureSlugAvailable,
  getWorktreeRoot,
  persistSlug,
  projectName,
  resolveSlug
} from "../lib/slug.js";
import {
  installDeps,
  spawnApps,
  spawnStripeListener,
  syncEnvSymlinks
} from "../services/apps.js";
import { bootSharedRedis, bootStack } from "../services/compose.js";
import {
  applyMigrations,
  waitForStorageTables,
  waitForTcp
} from "../services/migrations.js";
import {
  branchToPrefix,
  claimAppHosts,
  ensurePortlessInstalled,
  ensureProxyPrivileges,
  hostsFileInSync,
  proxyRunsAsRoot,
  pruneStaleRoutes,
  registerAliases,
  startProxyDaemon,
  syncHostsFile,
  waitForProxyReady
} from "../services/portless.js";
import { pickApps } from "../ui/prompts.js";
import { summaryLines } from "../ui/summary.js";
import { syncStaleCopyFiles } from "./copy.js";
import { down } from "./down.js";

export async function up(
  opts: { migrate?: boolean; regen?: boolean; apps?: boolean } = {}
) {
  const shouldMigrate = opts.migrate ?? true;
  // Type/swagger regen depends on a freshly-migrated schema. If migrations
  // were skipped, schema is unchanged — skip regen too.
  const shouldRegen = shouldMigrate && (opts.regen ?? true);
  // Services-only mode: boot compose stack + portless aliases (api/studio/
  // mail/inngest URLs still useful), skip spawnApps + auto-`down` on Ctrl+C.
  // Triggered by --no-apps OR by deselecting everything in the picker. User
  // runs `crbn down` to tear it back down.
  const appsRequested = opts.apps ?? true;
  intro("Carbon · dev up");

  await ensurePortlessInstalled();
  await ensureProxyPrivileges();

  const selectedApps = appsRequested ? await pickApps() : [];
  const shouldRunApps = selectedApps.length > 0;

  const root = await getWorktreeRoot();
  const slug = resolveSlug(root);
  await ensureSlugAvailable(slug, root);
  persistSlug(root, slug);
  log.info(`worktree: ${slug}  (project ${projectName(slug)})`);

  // Auto-heal stale `.env` (and other package.json#crbn.copy entries) from
  // main checkout. `crbn checkout <existing-branch>` skips do_post_create →
  // worktrees drift from main when new env vars land. Mtime-gated, so
  // unchanged files are untouched and local edits made *after* main's last
  // change are preserved.
  const refreshed = await syncStaleCopyFiles(root);
  if (refreshed.length > 0) {
    log.info(
      `refreshed ${refreshed.join(", ")} from main checkout (stale vs main)`
    );
  }

  // Outside `tasks` so pnpm progress streams directly when install runs.
  const ran = await installDeps(root);
  if (ran) log.step("pnpm install");
  else log.info("pnpm install skipped (lockfile in sync)");

  let ports!: Awaited<ReturnType<typeof resolveSlot>>["ports"];
  let redisDb!: number;
  let jwt!: Awaited<ReturnType<typeof resolveSlot>>["jwt"];
  let branchPrefix = "";
  let migrationsApplied = false;

  await tasks([
    {
      title: "Configure portless",
      task: async () => {
        const slot = await resolveSlot(slug, root);
        ports = slot.ports;
        redisDb = slot.redisDb;
        jwt = slot.jwt;

        // Prefix every non-default branch. Portless auto-prefixes only in
        // linked worktrees; main checkout gets the same shape via per-app
        // portless.json stamped below.
        const branch = await currentBranch(root);
        const linked = await isLinkedWorktree();
        branchPrefix = branchToPrefix(branch, slug);

        writeEnv(root, renderEnv({ slug, ports, redisDb, jwt, branchPrefix }));
        syncAppPortlessConfigs({ worktreeRoot: root, branchPrefix, linked });
        loadDotenv({ path: join(root, ".env.local"), override: false });
        loadDotenv({ path: join(root, ".env"), override: false });
        return `prefix "${branchPrefix}", redis db ${redisDb}`;
      }
    },
    {
      title: "Render .env.local & sync symlinks",
      task: async () => {
        await syncEnvSymlinks(root);
        return "env files synced";
      }
    },
    {
      title: "Boot shared redis",
      task: async () => {
        await bootSharedRedis(root);
        return `shared redis on :${SHARED_REDIS_PORT} (index ${redisDb})`;
      }
    },
    {
      title: "Boot docker compose stack",
      task: async (msg) => {
        msg("pulling/starting 12 services");
        await bootStack(root, slug);
        return "containers up";
      }
    },
    {
      title: "Wait for services",
      task: async (msg) => {
        msg("postgres + kong + inngest");
        await waitForTcp([
          `tcp:${ports.PORT_DB}`,
          `tcp:${ports.PORT_API}`,
          `tcp:${ports.PORT_INNGEST}`
        ]);
        msg("storage tables");
        await waitForStorageTables(ports.PORT_DB);
        return "all services responding";
      }
    },
    ...(shouldMigrate
      ? [
          {
            title: "Apply database migrations",
            task: async () => {
              const r = await applyMigrations(root, ports.PORT_DB);
              migrationsApplied = r.applied;
              return r.applied
                ? "migrations applied"
                : "schema already up to date";
            }
          }
        ]
      : [
          {
            title: "Skip database migrations (--no-migrate)",
            task: async () => "skipped"
          }
        ]),
    ...(shouldRegen
      ? [
          {
            title: "Regenerate types & swagger",
            task: async () => {
              if (!migrationsApplied) return "skipped (no new migrations)";
              await execa("pnpm", ["db:types"], { cwd: root });
              await execa("pnpm", ["generate:swagger"], { cwd: root });
              return "types + swagger refreshed";
            }
          }
        ]
      : []),
    {
      title: "Start portless proxy",
      task: async (msg) => {
        pruneStaleRoutes(branchPrefix);
        startProxyDaemon(root);
        msg("waiting for proxy on :443");
        await waitForProxyReady();
        return "proxy listening";
      }
    },
    {
      title: "Register service aliases",
      task: async () => {
        const count = await registerAliases(root, branchPrefix, ports);
        return `${count} aliases registered`;
      }
    },
    {
      title: "Reserve app hostnames",
      task: async () => {
        const killed = await claimAppHosts(branchPrefix, selectedApps);
        return killed > 0
          ? `killed ${killed} orphan portless process${killed === 1 ? "" : "es"}`
          : "no orphans found";
      }
    }
  ]);

  // Skip sudo sync when root daemon already auto-syncs, or hosts unchanged.
  if (proxyRunsAsRoot()) {
    log.info("/etc/hosts auto-synced by root proxy daemon");
  } else if (hostsFileInSync()) {
    log.info("/etc/hosts already in sync — skipping sudo");
  } else {
    log.step("sudo portless hosts sync");
    await syncHostsFile();
  }

  if (process.env.CARBON_EDITION === "cloud") {
    spawnStripeListener(root);
    log.info("stripe listener spawned (CARBON_EDITION=cloud)");
  }

  box(
    summaryLines(ports, branchPrefix, selectedApps).join("\n"),
    `Carbon dev — ${slug}`
  );

  if (!shouldRunApps) {
    outro("services up (run `crbn down` to stop)");
    return;
  }

  outro("apps starting (Ctrl+C to stop)");

  await spawnApps({ root, apps: selectedApps });

  // Apps exit on Ctrl+C; auto-`down` so compose stack isn't orphaned.
  // Swallow further signals so a second Ctrl+C during teardown doesn't
  // exit 130 mid-`docker compose stop`.
  const swallow = () => {
    process.stderr.write("\nfinishing teardown — please wait\n");
  };
  const SIGNALS = ["SIGINT", "SIGTERM", "SIGHUP", "SIGBREAK"] as const;
  for (const s of SIGNALS) process.on(s, swallow);
  try {
    // silent: post-SIGINT stdin raw-mode triggers EIO in clack's spinner.
    await down({ silent: true });
  } finally {
    for (const s of SIGNALS) process.off(s, swallow);
  }
}
