import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { basename, join } from "node:path";
import { execa } from "execa";

const SLUG_FILE = ".carbon-worktree";

export function resolveSlug(worktreeRoot: string): string {
  const fromEnv = process.env.CARBON_WORKTREE?.trim();
  if (fromEnv) return slugify(fromEnv);

  const filePath = join(worktreeRoot, SLUG_FILE);
  if (existsSync(filePath)) {
    const fromFile = readFileSync(filePath, "utf8").trim();
    if (fromFile) return slugify(fromFile);
  }

  return slugify(basename(worktreeRoot));
}

export function persistSlug(worktreeRoot: string, slug: string) {
  writeFileSync(join(worktreeRoot, SLUG_FILE), `${slug}\n`);
}

export async function getWorktreeRoot(): Promise<string> {
  try {
    const r = await execa("git", ["rev-parse", "--show-toplevel"]);
    return r.stdout.trim();
  } catch {
    return process.cwd();
  }
}

export function projectName(slug: string): string {
  return `carbon-${slug}`;
}

export async function ensureSlugAvailable(slug: string, worktreeRoot: string) {
  const project = projectName(slug);
  let runningPath: string | null = null;
  try {
    const r = await execa(
      "docker",
      [
        "ps",
        "--filter",
        `label=com.docker.compose.project=${project}`,
        "--format",
        '{{.Label "com.docker.compose.project.working_dir"}}'
      ],
      { reject: false }
    );
    const out = r.stdout.trim();
    if (out) runningPath = out.split("\n")[0] ?? null;
  } catch {
    return;
  }
  if (runningPath && runningPath !== worktreeRoot) {
    throw new Error(
      `Slug "${slug}" is already in use by another worktree at:\n  ${runningPath}\n\nSet CARBON_WORKTREE to a unique slug for this worktree, or stop the other stack.`
    );
  }
}

export function slugify(input: string): string {
  return input
    .toLowerCase()
    .replace(/[^a-z0-9-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .replace(/-+/g, "-");
}
