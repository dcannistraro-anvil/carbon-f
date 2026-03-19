import type { Database } from "@carbon/database";
import { SalesOrderEmail } from "@carbon/documents/email";
import type { sendEmailResendTask } from "@carbon/jobs/trigger/send-email-resend";
import { redis } from "@carbon/kv";
import { renderAsync } from "@react-email/components";
import type { SupabaseClient } from "@supabase/supabase-js";
import { tasks } from "@trigger.dev/sdk";
import type { LoaderFunctionArgs } from "react-router";
import { getPaymentTermsList } from "~/modules/accounting";
import {
  getCustomerContact,
  getSalesOrder,
  getSalesOrderCustomerDetails,
  getSalesOrderLines
} from "~/modules/sales";
import { getCompany } from "~/modules/settings";
import { getUser } from "~/modules/users/users.server";
import { stripSpecialCharacters } from "~/utils/string";
import { upsertDocument } from "../documents/documents.service";
import type { CustomFieldsTableType } from "../settings";

export async function assign(
  client: SupabaseClient<Database>,
  args: {
    id: string;
    table: string;
    assignee: string;
  }
) {
  const { id, table, assignee } = args;

  return (
    client
      // @ts-ignore
      .from(table)
      .update({ assignee: assignee ? assignee : null })
      .eq("id", id)
  );
}

export async function getCustomFieldsCacheKey(args?: {
  companyId?: string;
  module?: string;
  table?: string;
}) {
  return `customFields:${args?.companyId}:${args?.module ?? ""}:${
    args?.table ?? ""
  }`;
}

export async function getCustomFieldsSchemas(
  client: SupabaseClient<Database>,
  args?: {
    companyId: string;
    module?: string;
    table?: string;
  }
) {
  const key = await getCustomFieldsCacheKey(args);
  let schema: CustomFieldsTableType[] | null = null;

  try {
    schema = (await redis.get(key)) as CustomFieldsTableType[] | null;
  } finally {
    if (schema) {
      return {
        data: schema as CustomFieldsTableType[],
        error: null
      };
    }

    const query = client.from("customFieldTables").select("*");

    if (args?.companyId) {
      query.eq("companyId", args.companyId);
    }

    if (args?.module) {
      query.eq("module", args.module as any);
    }

    if (args?.table) {
      query.eq("table", args.table);
    }

    const result = await query;
    if (result.data) {
      await redis.set(key, JSON.stringify(result.data));
    }

    return result;
  }
}

/**
 * Generates a sales order PDF via the pdfLoader, uploads it to Supabase
 * storage under the opportunity path, and creates a document DB record.
 *
 * Returns the PDF ArrayBuffer (useful for email attachments) and the
 * generated file name.
 */
export async function generateAndAttachSalesOrderPdf(args: {
  /** The original action/loader args from the route */
  routeArgs: LoaderFunctionArgs;
  /** Sales order DB id */
  salesOrderId: string;
  /** Human-readable sales order identifier (e.g. "SO-0001") */
  salesOrderIdentifier: string;
  /** Opportunity the SO belongs to */
  opportunityId: string;
  companyId: string;
  userId: string;
  /** A service-role Supabase client for storage + DB writes */
  serviceRole: SupabaseClient<Database>;
  /** The pdf loader imported from the sales-order pdf route */
  pdfLoader: (args: LoaderFunctionArgs) => Promise<Response>;
}): Promise<{ file: ArrayBuffer; fileName: string }> {
  const {
    routeArgs,
    salesOrderId,
    salesOrderIdentifier,
    opportunityId,
    companyId,
    userId,
    serviceRole,
    pdfLoader
  } = args;

  // 1. Generate the PDF
  const pdfArgs = {
    ...routeArgs,
    params: { ...routeArgs.params, id: salesOrderId }
  };
  const pdf = await pdfLoader(pdfArgs);

  if (pdf.headers.get("content-type") !== "application/pdf") {
    throw new Error("Failed to generate PDF");
  }

  const file = await pdf.arrayBuffer();
  const fileName = stripSpecialCharacters(
    `${salesOrderIdentifier} - ${new Date().toISOString().slice(0, -5)}.pdf`
  );

  // 2. Upload to Supabase storage
  const documentFilePath = `${companyId}/opportunity/${opportunityId}/${fileName}`;

  const uploadResult = await serviceRole.storage
    .from("private")
    .upload(documentFilePath, file, {
      cacheControl: `${12 * 60 * 60}`,
      contentType: "application/pdf",
      upsert: true
    });

  if (uploadResult.error) {
    throw new Error("Failed to upload PDF to storage");
  }

  // 3. Create the document DB record
  const documentResult = await upsertDocument(serviceRole, {
    path: documentFilePath,
    name: fileName,
    size: Math.round(file.byteLength / 1024),
    sourceDocument: "Sales Order",
    sourceDocumentId: salesOrderId,
    readGroups: [userId],
    writeGroups: [userId],
    createdBy: userId,
    companyId
  });

  if (documentResult.error) {
    throw new Error("Failed to create document record");
  }

  return { file, fileName };
}

/**
 * Sends a sales order confirmation email with the PDF attached.
 *
 * This mirrors the email-sending logic originally in the confirm action
 * and can be reused by the quote-to-order conversion flow.
 */
export async function sendSalesOrderEmail(args: {
  salesOrderId: string;
  companyId: string;
  userId: string;
  customerContactId: string;
  cc?: string[];
  file: ArrayBuffer;
  fileName: string;
  serviceRole: SupabaseClient<Database>;
  locales: string[];
}): Promise<{ success: boolean; message?: string }> {
  const {
    salesOrderId,
    companyId,
    userId,
    customerContactId,
    cc: ccSelections,
    file,
    fileName,
    serviceRole,
    locales
  } = args;

  const [
    company,
    customer,
    salesOrder,
    salesOrderLines,
    salesOrderLocations,
    seller,
    paymentTerms
  ] = await Promise.all([
    getCompany(serviceRole, companyId),
    getCustomerContact(serviceRole, customerContactId),
    getSalesOrder(serviceRole, salesOrderId),
    getSalesOrderLines(serviceRole, salesOrderId),
    getSalesOrderCustomerDetails(serviceRole, salesOrderId),
    getUser(serviceRole, userId),
    getPaymentTermsList(serviceRole, companyId)
  ]);

  if (!customer?.data?.contact) {
    return { success: false, message: "Failed to get customer contact" };
  }
  if (!company.data) {
    return { success: false, message: "Failed to get company" };
  }
  if (!seller.data) {
    return { success: false, message: "Failed to get user" };
  }
  if (!salesOrder.data) {
    return { success: false, message: "Failed to get sales order" };
  }
  if (!salesOrderLocations.data) {
    return { success: false, message: "Failed to get sales order locations" };
  }
  if (!paymentTerms.data) {
    return { success: false, message: "Failed to get payment terms" };
  }

  const emailTemplate = SalesOrderEmail({
    company: company.data as any,
    locale: locales?.[0] ?? "en-US",
    salesOrder: salesOrder.data,
    salesOrderLines: salesOrderLines.data ?? [],
    salesOrderLocations: salesOrderLocations.data,
    recipient: {
      email: customer.data.contact.email!,
      firstName: customer.data.contact.firstName ?? undefined,
      lastName: customer.data.contact.lastName ?? undefined
    },
    sender: {
      email: seller.data.email,
      firstName: seller.data.firstName,
      lastName: seller.data.lastName
    },
    paymentTerms: paymentTerms.data
  });

  const html = await renderAsync(emailTemplate);
  const text = await renderAsync(emailTemplate, { plainText: true });

  await tasks.trigger<typeof sendEmailResendTask>("send-email-resend", {
    to: [seller.data.email, customer.data.contact.email!],
    cc: ccSelections?.length ? ccSelections : undefined,
    from: seller.data.email,
    subject: `Order ${salesOrder.data.salesOrderId} from ${company.data.name}`,
    html,
    text,
    attachments: [
      {
        content: Buffer.from(file).toString("base64"),
        filename: fileName
      }
    ],
    companyId
  });

  return { success: true };
}
