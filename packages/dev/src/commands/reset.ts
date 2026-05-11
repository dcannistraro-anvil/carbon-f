import { cancel, intro, log } from "@clack/prompts";
import { getSlot } from "../lib/ports.js";
import { getWorktreeRoot, projectName, resolveSlug } from "../lib/slug.js";
import { flushDb, stopStack } from "../services/compose.js";
import { confirmReset } from "../ui/prompts.js";
import { up } from "./up.js";

export async function reset() {
  intro("Carbon · dev reset");
  const root = await getWorktreeRoot();
  const slug = resolveSlug(root);

  if (!(await confirmReset(projectName(slug)))) {
    cancel("reset aborted");
    process.exit(0);
  }

  log.warn(`resetting ${projectName(slug)}`);
  await stopStack(root, slug, true);
  const slot = getSlot(slug);
  if (slot && typeof slot.redisDb === "number") {
    await flushDb(slot.redisDb);
  }
  await up();
}
