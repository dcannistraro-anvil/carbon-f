import { assertIsPost, error, success } from "@carbon/auth";
import { requirePermissions } from "@carbon/auth/auth.server";
import { flash } from "@carbon/auth/session.server";
import { validationError, validator } from "@carbon/form";
import { msg } from "@lingui/core/macro";
import type { ActionFunctionArgs } from "react-router";
import { redirect } from "react-router";
import { jobCompleteValidator } from "~/modules/production";
import type { Handle } from "~/utils/handle";
import { path, requestReferrer } from "~/utils/path";

export const handle: Handle = {
  breadcrumb: msg`Jobs`,
  to: path.to.jobs,
  module: "production"
};

export async function action({ request, params }: ActionFunctionArgs) {
  assertIsPost(request);
  const { client, companyId, userId } = await requirePermissions(request, {
    update: "production"
  });

  const formData = await request.formData();
  const validation = await validator(jobCompleteValidator).validate(formData);

  if (validation.error) {
    return validationError(validation.error);
  }

  const { jobId } = params;
  if (!jobId) throw new Error("Could not find jobId");

  const {
    quantityComplete,
    salesOrderId,
    salesOrderLineId,
    locationId,
    storageUnitId,
    leftoverAction,
    leftoverShipQuantity,
    leftoverReceiveQuantity
  } = validation.data;

  const makeToOrder = !!salesOrderId || !!salesOrderLineId;

  // Get job data to calculate leftovers
  const job = await client
    .from("job")
    .select("quantity")
    .eq("id", jobId)
    .single();
  if (job.error) {
    throw redirect(
      requestReferrer(request) ?? path.to.job(jobId),
      await flash(request, error(job.error, "Failed to get job data"))
    );
  }

  const originalQuantity = job.data?.quantity ?? 0;
  const leftoverQuantity = Math.max(0, quantityComplete - originalQuantity);
  const hasLeftover = leftoverQuantity > 0;

  // Calculate what to ship vs receive based on leftover action
  let quantityToShip = originalQuantity; // Default: ship original quantity
  let quantityToReceiveToInventory = 0;

  if (hasLeftover && leftoverAction) {
    switch (leftoverAction) {
      case "ship":
        // Ship all completed (including leftovers) to customer
        quantityToShip = quantityComplete;
        break;
      case "receive":
        // Ship original quantity, receive leftovers to inventory
        quantityToShip = originalQuantity;
        quantityToReceiveToInventory = leftoverQuantity;
        break;
      case "split":
        // Ship original + specified amount, receive rest to inventory
        quantityToShip = originalQuantity + (leftoverShipQuantity ?? 0);
        quantityToReceiveToInventory = leftoverReceiveQuantity ?? 0;
        break;
      case "discard":
        // Ship original quantity, discard leftovers (no action)
        quantityToShip = originalQuantity;
        break;
    }
  }

  if (makeToOrder) {
    const makeToOrderUpdate = await client
      .from("job")
      .update({
        status: "Completed" as const,
        completedDate: new Date().toISOString(),
        quantityComplete,
        quantityShipped: quantityToShip,
        updatedAt: new Date().toISOString(),
        updatedBy: userId
      })
      .eq("id", jobId);

    if (makeToOrderUpdate.error) {
      throw redirect(
        requestReferrer(request) ?? path.to.job(jobId),
        await flash(
          request,
          error(makeToOrderUpdate.error, "Failed to complete job")
        )
      );
    }

    // If we need to receive leftovers to inventory
    if (quantityToReceiveToInventory > 0) {
      const rpc = await client.rpc("complete_job_to_inventory", {
        p_job_id: jobId,
        p_quantity_complete: quantityToReceiveToInventory,
        p_storage_unit_id: storageUnitId ?? undefined,
        p_location_id: locationId ?? undefined,
        p_company_id: companyId,
        p_user_id: userId
      });

      if (rpc.error) {
        throw redirect(
          requestReferrer(request) ?? path.to.job(jobId),
          await flash(
            request,
            error(rpc.error, "Failed to receive leftovers to inventory")
          )
        );
      }
    }
  } else {
    // Make-to-stock: receive all completed to inventory
    const rpc = await client.rpc("complete_job_to_inventory", {
      p_job_id: jobId,
      p_quantity_complete: quantityComplete,
      p_storage_unit_id: storageUnitId ?? undefined,
      p_location_id: locationId ?? undefined,
      p_company_id: companyId,
      p_user_id: userId
    });

    if (rpc.error) {
      throw redirect(
        requestReferrer(request) ?? path.to.job(jobId),
        await flash(request, error(rpc.error, "Failed to complete job"))
      );
    }
  }

  throw redirect(
    requestReferrer(request) ?? path.to.job(jobId),
    await flash(request, success("Job completed successfully"))
  );
}
