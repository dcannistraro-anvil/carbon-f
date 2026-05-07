import type { Events } from "./events.ts";
import { inngest } from "./inngest/client.ts";

/**
 * Map trigger.dev task IDs → inngest event names.
 * This allows callers to migrate from `tasks.trigger("notify", payload)`
 * to `trigger("notify", payload)` with minimal changes.
 */
const taskToEvent = {
  notify: "carbon/notify",
  "send-email": "carbon/send-email",
  "model-thumbnail": "carbon/model-thumbnail",
  "update-permissions": "carbon/update-permissions",
  recalculate: "carbon/recalculate",
  "user-admin": "carbon/user-admin",
  "schedule-job": "carbon/reschedule-job",
  "post-transactions": "carbon/post-transaction",
  onboard: "carbon/onboard",
  "accounting-backfill": "carbon/accounting-backfill",
  "sync-external-accounting": "carbon/sync-external-accounting",
  "sync-issue-from-jira": "carbon/jira-sync",
  "sync-issue-from-linear": "carbon/linear-sync",
  "paperless-parts": "carbon/paperless-parts",
  "slack-document-created": "carbon/slack-document-created",
  "slack-document-status-update": "carbon/slack-document-status-update",
  "slack-document-task-update": "carbon/slack-document-task-update",
  "slack-document-assignment-update": "carbon/slack-document-assignment-update"
} as const;

type TaskMap = typeof taskToEvent;

type TaskPayloads = {
  [K in keyof TaskMap]: TaskMap[K] extends keyof Events
    ? Events[TaskMap[K]]["data"]
    : never;
};

/**
 * Typed trigger helper — drop-in replacement for `tasks.trigger(taskId, payload)`.
 *
 * @example
 * ```ts
 * import { trigger } from "@carbon/jobs";
 * await trigger("notify", { event, companyId, documentId, recipient });
 * ```
 */
export async function trigger<T extends keyof TaskPayloads>(
  taskId: T,
  payload: TaskPayloads[T]
) {
  const eventName = taskToEvent[taskId];
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return inngest.send({ name: eventName, data: payload } as any);
}

/**
 * Typed batch trigger helper — drop-in replacement for `tasks.batchTrigger(taskId, items)`.
 *
 * @example
 * ```ts
 * import { batchTrigger } from "@carbon/jobs";
 * await batchTrigger("recalculate", items.map(i => ({ payload: i })));
 * ```
 */
export async function batchTrigger<T extends keyof TaskPayloads>(
  taskId: T,
  items: Array<{ payload: TaskPayloads[T] }>
) {
  const eventName = taskToEvent[taskId];
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return inngest.send(
    items.map((i) => ({ name: eventName, data: i.payload })) as any
  );
}
