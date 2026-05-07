import { GTM_EVENTS_API_SECRET_KEY, GTM_URL } from "@carbon/env";

export async function forwardToGtm(
  type: string,
  metadata: Record<string, unknown>
): Promise<void> {
  if (!GTM_URL || !GTM_EVENTS_API_SECRET_KEY) {
    console.error("[gtm-events] missing GTM_URL or GTM_EVENTS_API_SECRET_KEY");
    return;
  }

  try {
    const res = await fetch(`${GTM_URL}/api/events`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-gtm-events-key": GTM_EVENTS_API_SECRET_KEY
      },
      body: JSON.stringify({ type, metadata })
    });

    if (!res.ok) {
      const body = await res.text().catch(() => "");
      console.error(`[gtm-events] ${res.status}: ${body}`);
    }
  } catch (err) {
    console.error("[gtm-events] request failed", err);
  }
}
