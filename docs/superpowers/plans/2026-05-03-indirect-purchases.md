# Indirect Purchases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GL Account (indirect) line support to purchase orders, purchase invoices, and supplier quotes, with mixed direct/indirect lines on a single document.

**Architecture:** Tabs inside the line form (ModalCard) switch between Direct and Indirect forms. The validator accepts both `methodItemType` and `"G/L Account"`. Status logic treats GL Account lines as always-received. Receipt creation skips them. Invoice posting debits the specified GL account directly.

**Tech Stack:** React, Zod, Supabase/Postgres, react-pdf

**Already in place:**
- `CostCenter` form component exists at `apps/erp/app/components/Form/CostCenter.tsx`
- `Account` form component exists at `apps/erp/app/components/Form/Account.tsx`
- `accountId` column exists on `purchaseOrderLine` and `purchaseInvoiceLine` (from company-groups migration)
- `post-purchase-invoice` edge function already has a `case "G/L Account"` handler that debits the specified account directly
- `PurchaseOrderPDF` utils already handle GL Account lines in `getLineDescription` and `getLineDescriptionDetails`
- Receipt creation already filters to only `["Part", "Material", "Tool", "Fixture", "Consumable"]` lines

---

### Task 1: DB Migration — Add costCenterId to purchase order and invoice lines

**Files:**
- Create: `packages/database/supabase/migrations/20260503000000_indirect-purchases.sql`

- [ ] **Step 1: Create migration file**

```sql
ALTER TABLE "purchaseOrderLine" ADD COLUMN "costCenterId" TEXT;
ALTER TABLE "purchaseOrderLine" ADD CONSTRAINT "purchaseOrderLine_costCenterId_fkey"
  FOREIGN KEY ("costCenterId") REFERENCES "costCenter"("id") ON DELETE SET NULL ON UPDATE CASCADE;
CREATE INDEX "purchaseOrderLine_costCenterId_idx" ON "purchaseOrderLine"("costCenterId");

ALTER TABLE "purchaseInvoiceLine" ADD COLUMN "costCenterId" TEXT;
ALTER TABLE "purchaseInvoiceLine" ADD CONSTRAINT "purchaseInvoiceLine_costCenterId_fkey"
  FOREIGN KEY ("costCenterId") REFERENCES "costCenter"("id") ON DELETE SET NULL ON UPDATE CASCADE;
CREATE INDEX "purchaseInvoiceLine_costCenterId_idx" ON "purchaseInvoiceLine"("costCenterId");

ALTER TABLE "supplierQuoteLine" ADD COLUMN "costCenterId" TEXT;
ALTER TABLE "supplierQuoteLine" ADD CONSTRAINT "supplierQuoteLine_costCenterId_fkey"
  FOREIGN KEY ("costCenterId") REFERENCES "costCenter"("id") ON DELETE SET NULL ON UPDATE CASCADE;
CREATE INDEX "supplierQuoteLine_costCenterId_idx" ON "supplierQuoteLine"("costCenterId");

ALTER TABLE "supplierQuoteLine" ADD COLUMN "accountId" TEXT;
ALTER TABLE "supplierQuoteLine" ADD CONSTRAINT "supplierQuoteLine_accountId_fkey"
  FOREIGN KEY ("accountId") REFERENCES "account"("id") ON DELETE SET NULL ON UPDATE CASCADE;
CREATE INDEX "supplierQuoteLine_accountId_idx" ON "supplierQuoteLine"("accountId");

ALTER TABLE "supplierQuoteLine" ADD COLUMN "supplierQuoteLineType" TEXT NOT NULL DEFAULT 'Part';
```

- [ ] **Step 2: Verify migration compiles**

Visually inspect the SQL for syntax errors. Do NOT run the migration — wait for the user to rebuild the database.

- [ ] **Step 3: Commit**

```bash
git add packages/database/supabase/migrations/20260503000000_indirect-purchases.sql
git commit -m "feat: add costCenterId, accountId, and lineType to purchase and invoice lines"
```

---

### Task 2: Update validators and models — purchasing

**Files:**
- Modify: `apps/erp/app/modules/purchasing/purchasing.models.ts`

- [ ] **Step 1: Add "G/L Account" to purchaseOrderLineType**

In `apps/erp/app/modules/purchasing/purchasing.models.ts`, change lines 35-44 from:

```typescript
export const purchaseOrderLineType = [
  "Part",
  // "Service",
  "Material",
  "Tool",
  "Consumable",
  // "G/L Account",
  // "Fixed Asset",
  "Comment"
] as const;
```

to:

```typescript
export const purchaseOrderLineType = [
  "Part",
  // "Service",
  "Material",
  "Tool",
  "Consumable",
  "G/L Account",
  // "Fixed Asset",
  "Comment"
] as const;
```

- [ ] **Step 2: Update purchaseOrderLineValidator to accept G/L Account**

Change the validator's `purchaseOrderLineType` field (line 193) from:

```typescript
    purchaseOrderLineType: z.enum(methodItemType, {
      errorMap: (issue, ctx) => ({
        message: "Type is required"
      })
    }),
```

to:

```typescript
    purchaseOrderLineType: z.enum([...methodItemType, "G/L Account"], {
      errorMap: (issue, ctx) => ({
        message: "Type is required"
      })
    }),
```

- [ ] **Step 3: Add costCenterId field to the validator**

In the `purchaseOrderLineValidator` object (after `accountId` on line 199), add:

```typescript
    costCenterId: zfd.text(z.string().optional()),
```

- [ ] **Step 4: Uncomment the G/L Account refinement**

After the existing `.refine(...)` block (after line 228), uncomment and add the G/L Account refinement:

```typescript
  .refine(
    (data) =>
      data.purchaseOrderLineType === "G/L Account" ? data.accountId : true,
    {
      message: "Account is required",
      path: ["accountId"]
    }
  );
```

Remove the old commented-out refinements (lines 229-252) and replace with just the G/L Account one above.

- [ ] **Step 5: Update supplierQuoteLineValidator**

In the `supplierQuoteLineValidator` (lines 450-466), add support for GL Account lines. The current validator requires `itemId` always. Change to:

```typescript
export const supplierQuoteLineValidator = z
  .object({
    id: zfd.text(z.string().optional()),
    supplierQuoteId: z.string(),
    supplierQuoteLineType: z.enum([...methodItemType, "G/L Account"], {
      errorMap: () => ({ message: "Type is required" })
    }),
    itemId: zfd.text(z.string().optional()),
    accountId: zfd.text(z.string().optional()),
    costCenterId: zfd.text(z.string().optional()),
    description: zfd.text(z.string().optional()),
    supplierPartId: zfd.text(z.string().optional()),
    inventoryUnitOfMeasureCode: zfd.text(z.string().optional()),
    purchaseUnitOfMeasureCode: zfd.text(z.string().optional()),
    conversionFactor: zfd.numeric(z.number().optional()),
    quantity: z.array(
      zfd.numeric(z.number().min(0.00001, { message: "Quantity is required" }))
    )
  })
  .refine(
    (data) =>
      ["Part", "Service", "Material", "Tool", "Fixture", "Consumable"].includes(
        data.supplierQuoteLineType
      )
        ? data.itemId
        : true,
    {
      message: "Part is required",
      path: ["itemId"]
    }
  )
  .refine(
    (data) =>
      data.supplierQuoteLineType === "G/L Account" ? data.accountId : true,
    {
      message: "Account is required",
      path: ["accountId"]
    }
  )
  .refine(
    (data) =>
      ["Part", "Service", "Material", "Tool", "Fixture", "Consumable"].includes(
        data.supplierQuoteLineType
      )
        ? data.description
        : true,
    {
      message: "Description is required",
      path: ["description"]
    }
  );
```

- [ ] **Step 6: Commit**

```bash
git add apps/erp/app/modules/purchasing/purchasing.models.ts
git commit -m "feat: update purchasing validators for GL Account line type"
```

---

### Task 3: Update validators and models — invoicing

**Files:**
- Modify: `apps/erp/app/modules/invoicing/invoicing.models.ts`

- [ ] **Step 1: Add "G/L Account" to purchaseInvoiceLineType**

In `apps/erp/app/modules/invoicing/invoicing.models.ts`, change lines 5-14 from:

```typescript
export const purchaseInvoiceLineType = [
  "Part",
  // "Service",
  "Material",
  "Tool",
  "Consumable",
  // "Fixed Asset",
  // "G/L Account",
  "Comment"
] as const;
```

to:

```typescript
export const purchaseInvoiceLineType = [
  "Part",
  // "Service",
  "Material",
  "Tool",
  "Consumable",
  // "Fixed Asset",
  "G/L Account",
  "Comment"
] as const;
```

- [ ] **Step 2: Update purchaseInvoiceLineValidator to accept G/L Account**

Change the `invoiceLineType` field (line 105) from:

```typescript
    invoiceLineType: z.enum(methodItemType, {
```

to:

```typescript
    invoiceLineType: z.enum([...methodItemType, "G/L Account"], {
```

- [ ] **Step 3: Add costCenterId field**

After `accountId` (line 113), add:

```typescript
    costCenterId: zfd.text(z.string().optional()),
```

- [ ] **Step 4: Uncomment G/L Account refinement and update location refinement**

After the existing location refinement (line 148), add:

```typescript
  .refine(
    (data) =>
      data.invoiceLineType === "G/L Account" ? data.accountId : true,
    {
      message: "Account is required",
      path: ["accountId"]
    }
  );
```

Remove the old commented-out refinements (lines 149-170).

- [ ] **Step 5: Commit**

```bash
git add apps/erp/app/modules/invoicing/invoicing.models.ts
git commit -m "feat: update invoicing validators for GL Account line type"
```

---

### Task 4: Update PurchaseOrderLineForm with Direct/Indirect tabs

**Files:**
- Modify: `apps/erp/app/modules/purchasing/ui/PurchaseOrder/PurchaseOrderLineForm.tsx`

- [ ] **Step 1: Add tab imports and Account/CostCenter form components**

Add to the imports at the top of the file:

```typescript
import {
  Tabs,
  TabsContent,
  TabsList,
  TabsTrigger
} from "@carbon/react";
```

These are already available from `@carbon/react` but not currently imported in this file. Also add the form component imports:

```typescript
import { Account, CostCenter } from "~/components/Form";
```

And add icons for the tabs:

```typescript
import { LuBox, LuReceipt } from "react-icons/lu";
```

- [ ] **Step 2: Add tab state**

After the `isEditing` variable (line 152), add:

```typescript
  const isGLAccount = initialValues.purchaseOrderLineType === "G/L Account";
  const [activeTab, setActiveTab] = useState<"direct" | "indirect">(
    isGLAccount ? "indirect" : "direct"
  );
```

- [ ] **Step 3: Add indirect line state**

After the existing `itemData` state, add state for indirect line data:

```typescript
  const [indirectData, setIndirectData] = useState<{
    accountId: string;
    costCenterId: string;
    description: string;
    purchaseQuantity: number;
    supplierUnitPrice: number;
    supplierShippingCost: number;
    supplierTaxAmount: number;
    taxPercent: number;
  }>({
    accountId: initialValues.accountId ?? "",
    costCenterId: initialValues.costCenterId ?? "",
    description: initialValues.description ?? "",
    purchaseQuantity: initialValues.purchaseQuantity ?? 1,
    supplierUnitPrice: initialValues.supplierUnitPrice ?? 0,
    supplierShippingCost: initialValues.supplierShippingCost ?? 0,
    supplierTaxAmount: initialValues.supplierTaxAmount ?? 0,
    taxPercent: 0
  });
```

Add tax calculation effect for indirect data (similar to the existing one for itemData):

```typescript
  useEffect(() => {
    const subtotal =
      indirectData.supplierUnitPrice * indirectData.purchaseQuantity +
      indirectData.supplierShippingCost;
    if (indirectData.taxPercent !== 0) {
      setIndirectData((d) => ({
        ...d,
        supplierTaxAmount: subtotal * indirectData.taxPercent
      }));
    }
  }, [
    indirectData.supplierUnitPrice,
    indirectData.purchaseQuantity,
    indirectData.supplierShippingCost,
    indirectData.taxPercent
  ]);
```

- [ ] **Step 4: Wrap form body with Tabs when creating new lines**

In the JSX, wrap the `ModalCardBody` content with Tabs. The key structural change: when `!isEditing`, render tabs around two `TabsContent` blocks. When `isEditing`, render only the appropriate form (no tabs).

Replace the existing `<ModalCardBody>` section with a structure like:

```tsx
<ModalCardBody>
  <Hidden name="id" />
  <Hidden name="purchaseOrderId" />
  <Hidden
    name="exchangeRate"
    value={routeData?.purchaseOrder?.exchangeRate ?? 1}
  />

  {!isEditing ? (
    <Tabs value={activeTab} onValueChange={(v) => setActiveTab(v as "direct" | "indirect")}>
      <TabsList className="mb-4">
        <TabsTrigger value="direct">
          <LuBox className="mr-1" />
          Direct
        </TabsTrigger>
        <TabsTrigger value="indirect">
          <LuReceipt className="mr-1" />
          Indirect
        </TabsTrigger>
      </TabsList>
      <TabsContent value="direct">
        {/* existing direct form fields — move them here */}
        <Hidden name="purchaseOrderLineType" value={itemType} />
        <Hidden name="description" value={itemData.description} />
        <Hidden name="inventoryUnitOfMeasureCode" value={itemData?.inventoryUom} />
        {/* ... all existing form fields ... */}
      </TabsContent>
      <TabsContent value="indirect">
        <Hidden name="purchaseOrderLineType" value="G/L Account" />
        <Hidden name="description" value={indirectData.description} />
        <VStack>
          <div className="grid w-full gap-x-8 gap-y-4 grid-cols-1 lg:grid-cols-3">
            <Account name="accountId" label={t`GL Account`} />
            <FormControl>
              <FormLabel>
                <Trans>Description</Trans>
              </FormLabel>
              <Input
                value={indirectData.description}
                onChange={(e) =>
                  setIndirectData((d) => ({
                    ...d,
                    description: e.target.value
                  }))
                }
              />
            </FormControl>
            <CostCenter name="costCenterId" label={t`Cost Center`} isOptional />
            <NumberControlled
              name="purchaseQuantity"
              label={t`Quantity`}
              value={indirectData.purchaseQuantity}
              onChange={(value) =>
                setIndirectData((d) => ({ ...d, purchaseQuantity: value }))
              }
            />
            <NumberControlled
              name="supplierUnitPrice"
              label={t`Unit Price`}
              value={indirectData.supplierUnitPrice}
              formatOptions={{
                style: "currency",
                currency:
                  routeData?.purchaseOrder?.currencyCode ??
                  company.baseCurrencyCode
              }}
              onChange={(value) =>
                setIndirectData((d) => ({ ...d, supplierUnitPrice: value }))
              }
            />
            <NumberControlled
              name="supplierShippingCost"
              label={t`Shipping`}
              minValue={0}
              value={indirectData.supplierShippingCost}
              formatOptions={{
                style: "currency",
                currency:
                  routeData?.purchaseOrder?.currencyCode ??
                  company.baseCurrencyCode
              }}
              onChange={(value) =>
                setIndirectData((d) => ({ ...d, supplierShippingCost: value }))
              }
            />
            <NumberControlled
              name="supplierTaxAmount"
              label={t`Tax`}
              value={indirectData.supplierTaxAmount}
              formatOptions={{
                style: "currency",
                currency:
                  routeData?.purchaseOrder?.currencyCode ??
                  company.baseCurrencyCode
              }}
              onChange={(value) => {
                const subtotal =
                  indirectData.supplierUnitPrice * indirectData.purchaseQuantity +
                  indirectData.supplierShippingCost;
                setIndirectData((d) => ({
                  ...d,
                  supplierTaxAmount: value,
                  taxPercent: subtotal > 0 ? value / subtotal : 0
                }));
              }}
            />
            <NumberControlled
              name="taxPercent"
              label={t`Tax Percent`}
              value={indirectData.taxPercent}
              minValue={0}
              maxValue={1}
              step={0.0001}
              formatOptions={{
                style: "percent",
                minimumFractionDigits: 0,
                maximumFractionDigits: 2
              }}
              onChange={(value) => {
                const subtotal =
                  indirectData.supplierUnitPrice * indirectData.purchaseQuantity +
                  indirectData.supplierShippingCost;
                setIndirectData((d) => ({
                  ...d,
                  taxPercent: value,
                  supplierTaxAmount: subtotal * value
                }));
              }}
            />
            <CustomFormFields table="purchaseOrderLine" />
          </div>
        </VStack>
      </TabsContent>
    </Tabs>
  ) : isGLAccount ? (
    // Editing an existing GL Account line — show indirect fields only, no tabs
    <>
      <Hidden name="purchaseOrderLineType" value="G/L Account" />
      <Hidden name="description" value={indirectData.description} />
      {/* same indirect fields as above */}
    </>
  ) : (
    // Editing an existing direct line — show direct fields only, no tabs
    <>
      <Hidden name="purchaseOrderLineType" value={itemType} />
      <Hidden name="description" value={itemData.description} />
      <Hidden name="inventoryUnitOfMeasureCode" value={itemData?.inventoryUom} />
      {/* existing direct form fields */}
    </>
  )}
</ModalCardBody>
```

The key principle: extract the existing direct form fields into a reusable block, and add the indirect block alongside it. Do not duplicate the Hidden fields that are shared (id, purchaseOrderId, exchangeRate).

- [ ] **Step 5: Commit**

```bash
git add apps/erp/app/modules/purchasing/ui/PurchaseOrder/PurchaseOrderLineForm.tsx
git commit -m "feat: add Direct/Indirect tabs to PurchaseOrderLineForm"
```

---

### Task 5: Update PurchaseOrderExplorer for GL Account lines

**Files:**
- Modify: `apps/erp/app/modules/purchasing/ui/PurchaseOrder/PurchaseOrderExplorer.tsx`

- [ ] **Step 1: Update PurchaseOrderLineItem to handle GL Account lines**

In the `PurchaseOrderLineItem` component (line 175), update the display logic. Currently it always shows `getItemReadableId(items, line.itemId)` (line 218). For GL Account lines, show the description instead.

Change lines 216-223 from:

```tsx
            <VStack spacing={0} className="min-w-0">
              <span className="font-semibold line-clamp-1">
                {getItemReadableId(items, line.itemId)}
              </span>
              <span className="text-muted-foreground text-xs truncate line-clamp-1">
                {line.description}
              </span>
            </VStack>
```

to:

```tsx
            <VStack spacing={0} className="min-w-0">
              <span className="font-semibold line-clamp-1">
                {line.purchaseOrderLineType === "G/L Account"
                  ? (line.description || "Indirect Expense")
                  : getItemReadableId(items, line.itemId)}
              </span>
              <span className="text-muted-foreground text-xs truncate line-clamp-1">
                {line.purchaseOrderLineType === "G/L Account"
                  ? "G/L Account"
                  : line.description}
              </span>
            </VStack>
```

- [ ] **Step 2: Update the "View Item Master" dropdown to hide for GL Account lines**

The existing check on line 251 already handles this partially:

```tsx
{methodItemType.includes(line?.purchaseOrderLineType ?? "") && (
```

Since `"G/L Account"` is not in `methodItemType`, this already correctly hides the "View Item Master" option. No change needed.

- [ ] **Step 3: Commit**

```bash
git add apps/erp/app/modules/purchasing/ui/PurchaseOrder/PurchaseOrderExplorer.tsx
git commit -m "feat: display GL Account lines in PurchaseOrderExplorer"
```

---

### Task 6: Update PurchaseInvoiceLineForm with Direct/Indirect tabs

**Files:**
- Modify: `apps/erp/app/modules/invoicing/ui/PurchaseInvoice/PurchaseInvoiceLineForm.tsx`

- [ ] **Step 1: Apply the same tab pattern as PurchaseOrderLineForm**

Follow the exact same pattern from Task 4: add Tabs imports, Account/CostCenter imports, tab state, indirect data state, and the Direct/Indirect tab UI. The fields for the indirect tab are the same: GL Account, Description, Cost Center, Quantity, Unit Price, Shipping, Tax Amount, Tax Percent.

The key differences from the PO form:
- The hidden field name is `invoiceLineType` instead of `purchaseOrderLineType`
- The validator is `purchaseInvoiceLineValidator`
- The currency comes from `routeData?.purchaseInvoice?.currencyCode`

- [ ] **Step 2: Commit**

```bash
git add apps/erp/app/modules/invoicing/ui/PurchaseInvoice/PurchaseInvoiceLineForm.tsx
git commit -m "feat: add Direct/Indirect tabs to PurchaseInvoiceLineForm"
```

---

### Task 7: Update SupplierQuoteLineForm with Direct/Indirect tabs

**Files:**
- Modify: `apps/erp/app/modules/purchasing/ui/SupplierQuote/SupplierQuoteLineForm.tsx`

- [ ] **Step 1: Apply the same tab pattern**

Add Direct/Indirect tabs to the supplier quote line form. The indirect tab for quotes should include: GL Account, Description, Cost Center, and the quantity array (since quotes support multiple quantity break points).

Key difference: supplier quote lines use `quantity` as an array of numbers (for price breaks), so the indirect form needs to use `ArrayNumeric` for quantities.

Add hidden field `supplierQuoteLineType` set to `"G/L Account"` for indirect tab.

- [ ] **Step 2: Commit**

```bash
git add apps/erp/app/modules/purchasing/ui/SupplierQuote/SupplierQuoteLineForm.tsx
git commit -m "feat: add Direct/Indirect tabs to SupplierQuoteLineForm"
```

---

### Task 8: Update status logic — getPurchaseOrderStatus

**Files:**
- Modify: `packages/utils/src/status.ts`

- [ ] **Step 1: Treat GL Account lines as always-received**

In `getPurchaseOrderStatus` (line 59), update the `allLinesReceived` check to treat GL Account lines like Comment lines — they should be treated as always received:

Change lines 70-72 from:

```typescript
  const allLinesReceived = lines.every(
    (line) => line.purchaseOrderLineType === "Comment" || line.receivedComplete
  );
```

to:

```typescript
  const allLinesReceived = lines.every(
    (line) =>
      line.purchaseOrderLineType === "Comment" ||
      line.purchaseOrderLineType === "G/L Account" ||
      line.receivedComplete
  );
```

The `allInvoices` check does NOT change — GL Account lines still need to be invoiced.

- [ ] **Step 2: Commit**

```bash
git add packages/utils/src/status.ts
git commit -m "feat: treat GL Account lines as always-received in status logic"
```

---

### Task 9: Update status logic — post-receipt edge function

**Files:**
- Modify: `packages/database/supabase/functions/post-receipt/index.ts`

- [ ] **Step 1: Update receipt posting status calculation**

In the post-receipt function, update the `areAllLinesReceived` check (line 1129-1131) to treat GL Account like Comment:

Change:

```typescript
          const areAllLinesReceived = purchaseOrderLines.every(
            (line) =>
              line.purchaseOrderLineType === "Comment" || line.receivedComplete
          );
```

to:

```typescript
          const areAllLinesReceived = purchaseOrderLines.every(
            (line) =>
              line.purchaseOrderLineType === "Comment" ||
              line.purchaseOrderLineType === "G/L Account" ||
              line.receivedComplete
          );
```

- [ ] **Step 2: Update receipt voiding status projection**

Similarly update the `areAllLinesReceivedProjected` check (lines 304-310):

Change:

```typescript
      const areAllLinesReceivedProjected = projectedPurchaseOrderLines.every(
        (line) => {
          if (line.purchaseOrderLineType === "Comment") return true;
```

to:

```typescript
      const areAllLinesReceivedProjected = projectedPurchaseOrderLines.every(
        (line) => {
          if (line.purchaseOrderLineType === "Comment" || line.purchaseOrderLineType === "G/L Account") return true;
```

Do the same for the `areAllLinesInvoicedProjected` check at line 297 — but only for the received check. GL Account lines still need invoicing, so do NOT add the GL Account exception to the invoiced check.

- [ ] **Step 3: Commit**

```bash
git add packages/database/supabase/functions/post-receipt/index.ts
git commit -m "feat: skip GL Account lines in receipt status calculations"
```

---

### Task 10: Update receipt creation — skip GL Account lines

**Files:**
- Modify: `packages/database/supabase/functions/create/index.ts`

- [ ] **Step 1: Add G/L Account to receipt line filter**

In the `receiptFromPurchaseOrder` case, the PO lines are already filtered to include only `["Part", "Material", "Tool", "Fixture", "Consumable"]` (line 791-797). This already excludes GL Account lines. No change needed here.

However, verify the secondary filter at lines 879-885 which excludes `"Service"` lines. Add `"G/L Account"` exclusion for safety:

Change the filter from:

```typescript
        .filter((d) => d.itemId && d.purchaseQuantity && d.purchaseOrderLineType !== "Service")
```

to:

```typescript
        .filter((d) => d.itemId && d.purchaseQuantity && d.purchaseOrderLineType !== "Service" && d.purchaseOrderLineType !== "G/L Account")
```

- [ ] **Step 2: Commit**

```bash
git add packages/database/supabase/functions/create/index.ts
git commit -m "feat: exclude GL Account lines from receipt creation"
```

---

### Task 11: Update PurchaseOrderHeader — Receive button logic

**Files:**
- Modify: `apps/erp/app/modules/purchasing/ui/PurchaseOrder/PurchaseOrderHeader.tsx`

- [ ] **Step 1: Hide Receive button when all lines are GL Account**

Add a computed value to check if the PO has any direct (receivable) lines:

After `const requiresShipment = isOutsideProcessing && !hasShipments;` (line 124), add:

```typescript
  const hasReceivableLines = useMemo(
    () =>
      routeData?.lines?.some(
        (line) =>
          line.purchaseOrderLineType !== "Comment" &&
          line.purchaseOrderLineType !== "G/L Account"
      ) ?? false,
    [routeData?.lines]
  );
```

Then wrap the Receive/Receipts button section (lines 366-434) with a condition:

```tsx
{hasReceivableLines && (
  // ... existing receipts/receive button JSX ...
)}
```

- [ ] **Step 2: Commit**

```bash
git add apps/erp/app/modules/purchasing/ui/PurchaseOrder/PurchaseOrderHeader.tsx
git commit -m "feat: hide Receive button when PO has only GL Account lines"
```

---

### Task 12: Update convert edge function — PO to Invoice

**Files:**
- Modify: `packages/database/supabase/functions/convert/index.ts`

- [ ] **Step 1: Verify PO to Invoice conversion carries GL Account fields**

Check the `purchaseOrderToPurchaseInvoice` case (lines 349-371). The existing mapping already copies:
- `invoiceLineType` ← `line.purchaseOrderLineType`
- `accountId` ← `line.accountId`

Add `costCenterId` to the mapping. In the line mapping object, add:

```typescript
        costCenterId: line.costCenterId,
```

- [ ] **Step 2: Update supplier quote to PO conversion**

In the `supplierQuoteToPurchaseOrder` case (lines 1495-1529), update the line mapping to carry over GL Account fields:

Add to the line mapping object:

```typescript
        purchaseOrderLineType: line.supplierQuoteLineType === "G/L Account"
          ? "G/L Account"
          : (line.item?.type ?? "Part"),
        accountId: line.accountId,
        costCenterId: line.costCenterId,
```

Replace the existing `purchaseOrderLineType` field which currently uses `line.item?.type` unconditionally.

- [ ] **Step 3: Update the line filter for supplier quote to PO**

The existing code filters lines that have `selectedLines[line.id].quantity > 0`. This should work for GL Account lines too since they have quantities. No filter change needed.

- [ ] **Step 4: Commit**

```bash
git add packages/database/supabase/functions/convert/index.ts
git commit -m "feat: carry GL Account fields through document conversions"
```

---

### Task 13: Update Purchase Order PDF

**Files:**
- Modify: `packages/documents/src/utils/purchase-order.ts`

- [ ] **Step 1: Verify getLineDescription handles GL Account**

The `getLineDescription` function already handles GL Account — it returns `line?.description`. No change needed.

- [ ] **Step 2: Update getLineDescriptionDetails to use account name**

The `getLineDescriptionDetails` function currently shows:

```typescript
    case "G/L Account":
      return `G/L Account: ${line?.accountNumber}`;
```

This references `accountNumber` which is the legacy field. Check the `purchaseOrderLines` view to see if it includes an account name via a join. If the view includes `accountName`, update to:

```typescript
    case "G/L Account":
      return line?.accountName ? `${line.accountName}` : "G/L Account";
```

If the view doesn't include account name, you'll need to either:
1. Update the `purchaseOrderLines` view to join the account table and include the name, OR
2. Keep the existing `accountNumber` reference if it still works (the view may still expose it)

Check the view definition before deciding.

- [ ] **Step 3: Commit**

```bash
git add packages/documents/src/utils/purchase-order.ts
git commit -m "feat: update PDF description for GL Account lines"
```

---

### Task 14: Route actions — no explicit changes needed

All three route actions use the `...d` spread from the validated form data:
- PO lines: `apps/erp/app/routes/x+/purchase-order+/$orderId.$lineId.details.tsx` and `$orderId.new.tsx`
- Invoice lines: `apps/erp/app/routes/x+/purchase-invoice+/$invoiceId.$lineId.details.tsx` and `$invoiceId.new.tsx`
- Quote lines: `apps/erp/app/routes/x+/supplier-quote+/$id.$lineId.details.tsx` and `$id.new.tsx`

Since we added `costCenterId`, `accountId`, and type fields to the validators in Tasks 2-3, these automatically flow through to the database upsert via `...d`. No explicit route action changes are needed.

**However**, verify after testing that all fields persist correctly. If any upsert function (e.g., `upsertSupplierQuoteLine`) explicitly lists allowed fields rather than accepting `...d`, those functions will need updating too.

---

### Task 15: Test end-to-end in browser

- [ ] **Step 1: Start dev server**

```bash
npm run dev
```

- [ ] **Step 2: Test creating a direct purchase order line**

Navigate to an existing PO in Draft status. Click "Add Line Item". Verify the Direct tab is selected by default. Create a Part line. Verify it saves correctly.

- [ ] **Step 3: Test creating an indirect purchase order line**

On the same PO, click "Add Line Item" again. Switch to the Indirect tab. Select a GL Account, enter a description, quantity, and unit price. Save. Verify it appears in the explorer with the description shown.

- [ ] **Step 4: Test status logic**

Create a PO with only GL Account lines. Finalize it. Verify the status goes to "To Invoice" (not "To Receive and Invoice"). Verify the Receive button is hidden.

Create a PO with mixed lines. Finalize it. Verify status is "To Receive and Invoice". Create a receipt — verify only direct lines appear. Post the receipt. Verify status changes to "To Invoice".

- [ ] **Step 5: Test invoice creation from PO**

On a PO with GL Account lines, click Invoice. Verify both direct and indirect lines appear on the invoice. Verify GL Account fields (accountId, costCenterId) are carried over.

- [ ] **Step 6: Test the PDF**

Preview the PDF for a PO with GL Account lines. Verify the description shows as primary text and the account number appears as muted secondary text.

- [ ] **Step 7: Commit any fixes**

```bash
git add -A
git commit -m "fix: address issues found during end-to-end testing"
```

---

### Task 16: Update the cache

- [ ] **Step 1: Update relevant cache files**

After all changes are committed, update the llm/cache files to reflect the new GL Account line support in purchasing, invoicing, and supplier quotes.

- [ ] **Step 2: Commit cache updates**

```bash
git add llm/cache/
git commit -m "docs: update cache with indirect purchase support"
```
