import {
  assertIsPost,
  error,
  getCarbonServiceRole,
  success
} from "@carbon/auth";
import { requirePermissions } from "@carbon/auth/auth.server";
import { flash } from "@carbon/auth/session.server";
import { FunctionRegion } from "@supabase/supabase-js";
import type { ActionFunctionArgs } from "react-router";
import { redirect } from "react-router";
import {
  getMaintenanceDispatch,
  isMaintenanceDispatchLocked
} from "~/modules/resources";
import { requireUnlocked } from "~/utils/lockedGuard.server";
import { path, requestReferrer } from "~/utils/path";

export async function action({ request, params }: ActionFunctionArgs) {
  assertIsPost(request);
  const { userId, companyId } = await requirePermissions(request, {
    delete: "resources"
  });

  const { dispatchId, itemId } = params;
  if (!dispatchId) throw new Error("Could not find dispatchId");
  if (!itemId) throw new Error("Could not find itemId");

  const { client: viewClient } = await requirePermissions(request, {
    view: "resources"
  });
  const dispatch = await getMaintenanceDispatch(viewClient, dispatchId);
  await requireUnlocked({
    request,
    isLocked: isMaintenanceDispatchLocked(dispatch.data?.status),
    redirectTo: path.to.maintenanceDispatch(dispatchId),
    message: "Cannot modify a locked dispatch. Reopen it first."
  });

  const serviceRole = await getCarbonServiceRole();

  const result = await serviceRole.functions.invoke("issue", {
    body: {
      type: "maintenanceDispatchUnissue",
      maintenanceDispatchItemId: itemId,
      companyId,
      userId
    },
    region: FunctionRegion.UsEast1
  });

  if (result.error) {
    console.error(result.error);
    throw redirect(
      requestReferrer(request) ?? path.to.maintenanceDispatch(dispatchId),
      await flash(request, error(result.error, "Failed to remove item"))
    );
  }

  throw redirect(
    requestReferrer(request) ?? path.to.maintenanceDispatch(dispatchId),
    await flash(request, success("Item removed and returned to inventory"))
  );
}
