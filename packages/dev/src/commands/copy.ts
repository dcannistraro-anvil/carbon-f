import { copyFileSync, existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { intro, log, outro } from "@clack/prompts";
import pc from "picocolors";
import { mainCheckoutRoot } from "../lib/git.js";

const DEFAULT_INCLUDES = [".env"];

// Copy files listed in package.json#crbn.copy from main checkout into cwd.
export async function copy() {
  intro("Carbon · copy");

  const cwd = process.cwd();
  const mainRoot = await mainCheckoutRoot();
  if (mainRoot === cwd) {
    log.warn("already in main checkout — nothing to copy");
    outro("");
    return;
  }

  const includes = readIncludes(mainRoot);
  let copied = 0;
  for (const rel of includes) {
    const src = join(mainRoot, rel);
    const dest = join(cwd, rel);
    if (!existsSync(src)) {
      log.warn(`${pc.dim(rel)} missing in main checkout — skipped`);
      continue;
    }
    copyFileSync(src, dest);
    log.info(`${pc.green("✓")} ${rel}`);
    copied++;
  }

  outro(
    `${copied} file${copied === 1 ? "" : "s"} copied from ${pc.dim(mainRoot)}`
  );
}

function readIncludes(mainRoot: string): string[] {
  const pkgPath = join(mainRoot, "package.json");
  if (!existsSync(pkgPath)) return DEFAULT_INCLUDES;
  try {
    const pkg = JSON.parse(readFileSync(pkgPath, "utf8")) as {
      crbn?: { copy?: unknown };
    };
    const list = pkg.crbn?.copy;
    if (Array.isArray(list) && list.every((s) => typeof s === "string")) {
      return list as string[];
    }
    // biome-ignore lint/suspicious/noEmptyBlockStatements: ignored using `--suppress`
  } catch {}
  return DEFAULT_INCLUDES;
}
