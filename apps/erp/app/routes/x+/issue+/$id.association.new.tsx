import { assertIsPost } from "@carbon/auth";
import { requirePermissions } from "@carbon/auth/auth.server";
import { validator } from "@carbon/form";
import type { ActionFunctionArgs } from "react-router";
import { getIssue, isIssueLocked } from "~/modules/quality";
import { issueAssociationValidator } from "~/modules/quality/quality.models";
import { requireUnlocked } from "~/utils/lockedGuard.server";
import { path } from "~/utils/path";

export async function action({ request, params }: ActionFunctionArgs) {
  assertIsPost(request);
  const { client, companyId, userId } = await requirePermissions(request, {
    update: "quality"
  });

  const { id: nonConformanceId } = params;
  if (!nonConformanceId) throw new Error("Could not find id");

  const { client: viewClient } = await requirePermissions(request, {
    view: "quality"
  });
  const issue = await getIssue(viewClient, nonConformanceId);
  await requireUnlocked({
    request,
    isLocked: isIssueLocked(issue.data?.status),
    redirectTo: path.to.issue(nonConformanceId),
    message: "Cannot modify a closed issue. Reopen it first."
  });

  const formData = await request.formData();
  const validation = await validator(issueAssociationValidator).validate(
    formData
  );

  if (validation.error) {
    return {
      success: false,
      message: "Invalid form data"
    };
  }

  const { type, id, lineId, quantity } = validation.data;

  switch (type) {
    case "items":
      const { error: itemError } = await client
        .from("nonConformanceItem")
        .insert({
          itemId: id,
          nonConformanceId,
          createdBy: userId,
          companyId: companyId,
          quantity: quantity ?? 0
        });

      if (itemError) {
        console.error(itemError);
        return {
          success: false,
          message: "Failed to create issue item"
        };
      }
      break;

    case "customers":
      const { error: customerError } = await client
        .from("nonConformanceCustomer")
        .insert({
          customerId: id,
          nonConformanceId,
          createdBy: userId,
          companyId: companyId
        });

      if (customerError) {
        console.error(customerError);
        return {
          success: false,
          message: "Failed to create issue customer"
        };
      }
      break;
    case "suppliers":
      const { error: supplierError } = await client
        .from("nonConformanceSupplier")
        .insert({
          supplierId: id,
          nonConformanceId,
          createdBy: userId,
          companyId: companyId
        });

      if (supplierError) {
        console.error(supplierError);
        return {
          success: false,
          message: "Failed to create issue supplier"
        };
      }
      break;
    case "jobOperations":
      const job = await client
        .from("job")
        .select("id, jobId")
        .eq("id", id)
        .single();
      if (job.error) {
        console.error(job.error);
        return {
          success: false,
          message: "Failed to create issue job operation"
        };
      }

      const jobOperation = await client
        .from("nonConformanceJobOperation")
        .insert({
          jobOperationId: lineId!,
          jobId: job.data?.id,
          jobReadableId: job.data?.jobId,
          nonConformanceId,
          createdBy: userId,
          companyId: companyId
        });

      if (jobOperation.error) {
        console.error(jobOperation.error);
        return {
          success: false,
          message: "Failed to create issue job operation"
        };
      }
      break;
    case "purchaseOrderLines":
      const purchaseOrder = await client
        .from("purchaseOrder")
        .select("id, purchaseOrderId")
        .eq("id", id)
        .single();
      if (purchaseOrder.error) {
        console.error(purchaseOrder.error);
        return {
          success: false,
          message: "Failed to create issue purchase order line"
        };
      }

      const purchaseOrderLine = await client
        .from("nonConformancePurchaseOrderLine")
        .insert({
          purchaseOrderLineId: lineId!,
          purchaseOrderId: purchaseOrder.data?.id,
          purchaseOrderReadableId: purchaseOrder.data?.purchaseOrderId,
          nonConformanceId,
          createdBy: userId,
          companyId: companyId
        });

      if (purchaseOrderLine.error) {
        console.error(purchaseOrderLine.error);
        return {
          success: false,
          message: "Failed to create issue purchase order line"
        };
      }
      break;
    case "salesOrderLines":
      const salesOrder = await client
        .from("salesOrder")
        .select("id, salesOrderId")
        .eq("id", id)
        .single();
      if (salesOrder.error) {
        console.error(salesOrder.error);
        return {
          success: false,
          message: "Failed to create issue sales order line"
        };
      }

      const salesOrderLine = await client
        .from("nonConformanceSalesOrderLine")
        .insert({
          salesOrderLineId: lineId!,
          salesOrderId: salesOrder.data?.id,
          salesOrderReadableId: salesOrder.data?.salesOrderId,
          nonConformanceId,
          createdBy: userId,
          companyId: companyId
        });

      if (salesOrderLine.error) {
        console.error(salesOrderLine.error);
        return {
          success: false,
          message: "Failed to create issue sales order line"
        };
      }
      break;
    case "shipmentLines":
      const shipment = await client
        .from("shipment")
        .select("id, shipmentId")
        .eq("id", id)
        .single();
      if (shipment.error) {
        console.error(shipment.error);
        return {
          success: false,
          message: "Failed to create issue shipment line"
        };
      }

      const shipmentLine = await client
        .from("nonConformanceShipmentLine")
        .insert({
          shipmentLineId: lineId!,
          shipmentId: shipment.data?.id,
          shipmentReadableId: shipment.data?.shipmentId,
          nonConformanceId,
          createdBy: userId,
          companyId: companyId
        });

      if (shipmentLine.error) {
        console.error(shipmentLine.error);
        return {
          success: false,
          message: "Failed to create issue shipment line"
        };
      }
      break;
    case "receiptLines":
      const receipt = await client
        .from("receipt")
        .select("id, receiptId")
        .eq("id", id)
        .single();
      if (receipt.error) {
        console.error(receipt.error);
        return {
          success: false,
          message: "Failed to create issue receipt line"
        };
      }

      const receiptLine = await client
        .from("nonConformanceReceiptLine")
        .insert({
          receiptLineId: lineId!,
          receiptId: receipt.data?.id,
          receiptReadableId: receipt.data?.receiptId,
          nonConformanceId,
          createdBy: userId,
          companyId: companyId
        });

      if (receiptLine.error) {
        console.error(receiptLine.error);
        return {
          success: false,
          message: "Failed to create issue receipt line"
        };
      }
      break;
    case "trackedEntities":
      const { error: trackedEntityError } = await client
        .from("nonConformanceTrackedEntity")
        .insert({
          trackedEntityId: id,
          nonConformanceId,
          createdBy: userId,
          companyId: companyId
        });

      if (trackedEntityError) {
        return {
          success: false,
          message: "Failed to create issue tracked entity"
        };
      }
      break;
  }

  return {
    success: true,
    message: "Association created"
  };
}
