import { assertIsPost, error, success } from "@carbon/auth";
import { requirePermissions } from "@carbon/auth/auth.server";
import { flash } from "@carbon/auth/session.server";
import { integrations as availableIntegrations } from "@carbon/ee";
import { getIntegrationServerHooks } from "@carbon/ee/hooks.server";
import type { ActionFunctionArgs } from "react-router";
import { redirect } from "react-router";
import {
  deactivateIntegration,
  invalidateIntegrationHealthCache
} from "~/modules/settings/settings.server";
import { path } from "~/utils/path";
import { requirePlan } from "~/utils/planGate.server";

export async function action({ request, params }: ActionFunctionArgs) {
  assertIsPost(request);
  const { client, companyId, userId } = await requirePermissions(request, {
    update: "settings"
  });

  await requirePlan({
    request,
    client,
    companyId,
    redirectTo: path.to.integrations
  });

  const { id: integrationId } = params;
  if (!integrationId) throw new Error("Integration ID not found");

  const integration = availableIntegrations.find((i) => i.id === integrationId);

  if (!integration) throw new Error("Integration not found");

  const update = await deactivateIntegration(client, {
    id: integrationId,
    companyId,
    updatedBy: userId
  });

  if (update.error) {
    throw redirect(
      path.to.integrations,
      await flash(
        request,
        error(update.error, "Failed to disconnect integration")
      )
    );
  }

  // Call the onUninstall hook if defined
  const hooks = getIntegrationServerHooks(integrationId);
  if (hooks?.onUninstall) {
    await hooks.onUninstall(companyId);
  }

  await invalidateIntegrationHealthCache(integrationId, companyId);

  throw redirect(
    path.to.integrations,
    await flash(
      request,
      success(`Disconnected ${integration.name} integration`)
    )
  );
}
