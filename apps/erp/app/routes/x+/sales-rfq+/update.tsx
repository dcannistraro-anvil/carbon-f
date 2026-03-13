import { requirePermissions } from "@carbon/auth/auth.server";
import type { ActionFunctionArgs } from "react-router";
import { isSalesRfqLocked } from "~/modules/sales";
import { requireUnlockedBulk } from "~/utils/lockedGuard.server";

export async function action({ request }: ActionFunctionArgs) {
  const { client, userId } = await requirePermissions(request, {
    update: "sales"
  });

  const formData = await request.formData();
  const ids = formData.getAll("ids");
  const field = formData.get("field");
  const value = formData.get("value");

  if (
    typeof field !== "string" ||
    (typeof value !== "string" && value !== null)
  ) {
    return { error: { message: "Invalid form data" }, data: null };
  }

  // Check if any of the selected RFQs are locked
  const salesRfqs = await client
    .from("salesRfq")
    .select("id, status")
    .in("id", ids as string[]);
  const lockedError = requireUnlockedBulk({
    statuses: (salesRfqs.data ?? []).map((r) => r.status),
    checkFn: isSalesRfqLocked,
    message: "Cannot modify a locked RFQ."
  });
  if (lockedError) return lockedError;

  switch (field) {
    case "customerContactId":
    case "customerEngineeringContactId":
    case "customerId":
    case "customerLocationId":
    case "customerReference":
    case "expirationDate":
    case "locationId":
    case "rfqDate":
    case "salesPersonId":
      return await client
        .from("salesRfq")
        .update({
          [field]: value ? value : null,
          updatedBy: userId,
          updatedAt: new Date().toISOString()
        })
        .in("id", ids as string[]);
    default:
      return { error: { message: "Invalid field" }, data: null };
  }
}
