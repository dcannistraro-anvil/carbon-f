import { assertIsPost, error } from "@carbon/auth";
import { requirePermissions } from "@carbon/auth/auth.server";
import { getCarbonServiceRole } from "@carbon/auth/client.server";
import { flash } from "@carbon/auth/session.server";
import { validationError, validator } from "@carbon/form";
import type { ActionFunctionArgs } from "react-router";
import { redirect } from "react-router";
import { issueValidator } from "~/services/models";
import { path, requestReferrer } from "~/utils/path";

export async function action({ request }: ActionFunctionArgs) {
  assertIsPost(request);
  const { userId, companyId } = await requirePermissions(request, {});

  const formData = await request.formData();
  const validation = await validator(issueValidator).validate(formData);

  // `validationError` is the shape `<ValidatedForm>` recognises — without it
  // a failed submission returns an opaque `{error}` blob the modal silently
  // discards, which is exactly the "Issue button does nothing" symptom.
  if (validation.error) {
    return validationError(validation.error);
  }

  const { jobOperationId, materialId, itemId, quantity, adjustmentType } =
    validation.data;

  const serviceRole = await getCarbonServiceRole();
  const issue = await serviceRole.functions.invoke("issue", {
    body: {
      id: jobOperationId,
      type: "partToOperation",
      itemId,
      materialId,
      quantity,
      adjustmentType,
      companyId,
      userId
    }
  });

  if (issue.error) {
    throw redirect(
      requestReferrer(request) ?? path.to.operations,
      await flash(request, error(issue.error, "Failed to issue material"))
    );
  }

  throw redirect(requestReferrer(request) ?? path.to.operations);
}
