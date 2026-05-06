# Accrual Accounting Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix COGS calculation, add journal entries at shipment, add dimensions to sales transactions, implement WIP accounting for manufacturing, and build a cost layer system on costLedger.

**Architecture:** Shared COGS calculation engine consumed by `post-shipment` and `post-sales-invoice`. Cost layers tracked via `costLedger.remainingQuantity` for FIFO/LIFO. WIP journal entries at material issuance and job completion in the `issue` edge function. All journal entries gated by `isInternalUser` flag. Dimensions (ItemPostingGroup, Location, CustomerType, CostCenter) attached to all journal lines via `journalLineDimension` table.

**Tech Stack:** Deno edge functions, Kysely query builder, Supabase (Postgres), Zod validation.

**Spec:** `docs/superpowers/specs/2026-05-03-accrual-accounting-design.md`

---

## File Structure

| File | Responsibility |
|------|---------------|
| `packages/database/supabase/migrations/20260504000000_cost-layers.sql` | Add `remainingQuantity` to costLedger, add `laborAbsorptionAccount` to accountDefault |
| `packages/database/supabase/migrations/20260504000001_cost-layers-backfill.sql` | Backfill `remainingQuantity` on existing costLedger entries |
| `packages/database/supabase/functions/shared/calculate-cogs.ts` | COGS calculation engine: Standard, Average, FIFO, LIFO |
| `packages/database/supabase/functions/update-purchased-prices/index.ts` | Set `remainingQuantity` on costLedger inserts |
| `packages/database/supabase/functions/post-shipment/index.ts` | Add journal entries (COGS + Inventory), dimensions, costLedger consumption |
| `packages/database/supabase/functions/post-sales-invoice/index.ts` | Remove COGS from SO-linked invoices, fix direct invoice COGS, add dimensions |
| `packages/database/supabase/functions/issue/index.ts` | WIP journal entries on material issuance, costLedger + FG journal entries on job completion |
| `packages/database/supabase/functions/lib/utils.ts` | Add `journalReference.to.job(id)` and `journalReference.to.materialIssue(id)` |

---

### Task 1: Migration — Add `remainingQuantity` and `laborAbsorptionAccount`

**Files:**
- Create: `packages/database/supabase/migrations/20260504000000_cost-layers.sql`

- [ ] **Step 1: Write the migration**

```sql
-- Add remainingQuantity to costLedger for FIFO/LIFO cost layers
ALTER TABLE "costLedger"
  ADD COLUMN IF NOT EXISTS "remainingQuantity" NUMERIC(12, 4) NOT NULL DEFAULT 0;

CREATE INDEX "costLedger_itemId_remainingQuantity_idx"
  ON "costLedger" ("itemId", "remainingQuantity")
  WHERE "remainingQuantity" > 0;

-- Add laborAbsorptionAccount to accountDefault
ALTER TABLE "accountDefault"
  ADD COLUMN IF NOT EXISTS "laborAbsorptionAccount" TEXT REFERENCES "account" ("id");
```

- [ ] **Step 2: Verify migration applies**

Run: `grep -c "remainingQuantity" packages/database/supabase/migrations/20260504000000_cost-layers.sql`
Expected: 3 (the column definition, the index, and the WHERE clause)

- [ ] **Step 3: Commit**

```bash
git add packages/database/supabase/migrations/20260504000000_cost-layers.sql
git commit -m "feat: add remainingQuantity to costLedger and laborAbsorptionAccount to accountDefault"
```

---

### Task 2: Migration — Backfill `remainingQuantity`

**Files:**
- Create: `packages/database/supabase/migrations/20260504000001_cost-layers-backfill.sql`

- [ ] **Step 1: Write the backfill migration**

This migration sets `remainingQuantity` on all existing costLedger entries. For Standard/Average items, set `remainingQuantity = quantity` on all inbound entries. For FIFO items, walk layers newest-to-oldest assigning remaining quantity until on-hand is accounted for. For LIFO items, walk oldest-to-newest.

```sql
-- Backfill remainingQuantity on existing costLedger entries
-- Step 1: Set remainingQuantity = quantity on all inbound entries as baseline
UPDATE "costLedger" cl
SET "remainingQuantity" = cl."quantity"
WHERE cl."itemLedgerType" IN ('Purchase', 'Positive Adjmt.', 'Output', 'Transfer')
  AND cl."quantity" > 0;

-- Step 2: For FIFO items, consume layers oldest-first based on current on-hand
-- This DO block walks each (itemId, companyId) pair and adjusts remainingQuantity
DO $$
DECLARE
  r RECORD;
  on_hand NUMERIC;
  remaining_to_assign NUMERIC;
  layer RECORD;
BEGIN
  -- Process each item+company with FIFO costing
  FOR r IN
    SELECT ic."itemId", ic."companyId"
    FROM "itemCost" ic
    WHERE ic."costingMethod" = 'FIFO'
  LOOP
    -- Get current on-hand from itemLedger
    SELECT COALESCE(SUM(il."quantity"), 0) INTO on_hand
    FROM "itemLedger" il
    WHERE il."itemId" = r."itemId"
      AND il."companyId" = r."companyId";

    IF on_hand <= 0 THEN
      -- No inventory: zero out all layers
      UPDATE "costLedger"
      SET "remainingQuantity" = 0
      WHERE "itemId" = r."itemId"
        AND "companyId" = r."companyId";
      CONTINUE;
    END IF;

    -- Zero out all layers first
    UPDATE "costLedger"
    SET "remainingQuantity" = 0
    WHERE "itemId" = r."itemId"
      AND "companyId" = r."companyId";

    -- Walk newest-to-oldest (in FIFO, oldest are consumed first, so newest remain)
    remaining_to_assign := on_hand;
    FOR layer IN
      SELECT cl."id", cl."quantity"
      FROM "costLedger" cl
      WHERE cl."itemId" = r."itemId"
        AND cl."companyId" = r."companyId"
        AND cl."quantity" > 0
        AND cl."itemLedgerType" IN ('Purchase', 'Positive Adjmt.', 'Output', 'Transfer')
      ORDER BY cl."postingDate" DESC, cl."createdAt" DESC
    LOOP
      EXIT WHEN remaining_to_assign <= 0;

      IF layer."quantity" <= remaining_to_assign THEN
        UPDATE "costLedger" SET "remainingQuantity" = layer."quantity" WHERE "id" = layer."id";
        remaining_to_assign := remaining_to_assign - layer."quantity";
      ELSE
        UPDATE "costLedger" SET "remainingQuantity" = remaining_to_assign WHERE "id" = layer."id";
        remaining_to_assign := 0;
      END IF;
    END LOOP;

    -- Gap handling: if on_hand > costLedger total, create synthetic entry
    IF remaining_to_assign > 0 THEN
      INSERT INTO "costLedger" (
        "itemLedgerType", "costLedgerType", "adjustment", "documentType",
        "itemId", "quantity", "cost", "remainingQuantity", "companyId", "postingDate"
      )
      SELECT
        CASE
          WHEN i."replenishmentSystem" IN ('Make', 'Buy and Make') THEN 'Output'::"itemLedgerType"
          ELSE 'Purchase'::"itemLedgerType"
        END,
        'Direct Cost'::"costLedgerType",
        false,
        CASE
          WHEN i."replenishmentSystem" IN ('Make', 'Buy and Make') THEN 'Job Receipt'::"itemLedgerDocumentType"
          ELSE 'Purchase Receipt'::"itemLedgerDocumentType"
        END,
        r."itemId",
        remaining_to_assign,
        remaining_to_assign * COALESCE(ic."unitCost", ic."standardCost", 0),
        remaining_to_assign,
        r."companyId",
        COALESCE(
          (SELECT MIN(il."postingDate") FROM "itemLedger" il WHERE il."itemId" = r."itemId" AND il."companyId" = r."companyId"),
          CURRENT_DATE
        )
      FROM "itemCost" ic
      JOIN "item" i ON i."id" = ic."itemId"
      WHERE ic."itemId" = r."itemId"
        AND ic."companyId" = r."companyId";
    END IF;
  END LOOP;

  -- Process LIFO items (walk oldest-to-newest, since newest are consumed first)
  FOR r IN
    SELECT ic."itemId", ic."companyId"
    FROM "itemCost" ic
    WHERE ic."costingMethod" = 'LIFO'
  LOOP
    SELECT COALESCE(SUM(il."quantity"), 0) INTO on_hand
    FROM "itemLedger" il
    WHERE il."itemId" = r."itemId"
      AND il."companyId" = r."companyId";

    IF on_hand <= 0 THEN
      UPDATE "costLedger"
      SET "remainingQuantity" = 0
      WHERE "itemId" = r."itemId"
        AND "companyId" = r."companyId";
      CONTINUE;
    END IF;

    UPDATE "costLedger"
    SET "remainingQuantity" = 0
    WHERE "itemId" = r."itemId"
      AND "companyId" = r."companyId";

    remaining_to_assign := on_hand;
    FOR layer IN
      SELECT cl."id", cl."quantity"
      FROM "costLedger" cl
      WHERE cl."itemId" = r."itemId"
        AND cl."companyId" = r."companyId"
        AND cl."quantity" > 0
        AND cl."itemLedgerType" IN ('Purchase', 'Positive Adjmt.', 'Output', 'Transfer')
      ORDER BY cl."postingDate" ASC, cl."createdAt" ASC
    LOOP
      EXIT WHEN remaining_to_assign <= 0;

      IF layer."quantity" <= remaining_to_assign THEN
        UPDATE "costLedger" SET "remainingQuantity" = layer."quantity" WHERE "id" = layer."id";
        remaining_to_assign := remaining_to_assign - layer."quantity";
      ELSE
        UPDATE "costLedger" SET "remainingQuantity" = remaining_to_assign WHERE "id" = layer."id";
        remaining_to_assign := 0;
      END IF;
    END LOOP;

    IF remaining_to_assign > 0 THEN
      INSERT INTO "costLedger" (
        "itemLedgerType", "costLedgerType", "adjustment", "documentType",
        "itemId", "quantity", "cost", "remainingQuantity", "companyId", "postingDate"
      )
      SELECT
        CASE
          WHEN i."replenishmentSystem" IN ('Make', 'Buy and Make') THEN 'Output'::"itemLedgerType"
          ELSE 'Purchase'::"itemLedgerType"
        END,
        'Direct Cost'::"costLedgerType",
        false,
        CASE
          WHEN i."replenishmentSystem" IN ('Make', 'Buy and Make') THEN 'Job Receipt'::"itemLedgerDocumentType"
          ELSE 'Purchase Receipt'::"itemLedgerDocumentType"
        END,
        r."itemId",
        remaining_to_assign,
        remaining_to_assign * COALESCE(ic."unitCost", ic."standardCost", 0),
        remaining_to_assign,
        r."companyId",
        COALESCE(
          (SELECT MIN(il."postingDate") FROM "itemLedger" il WHERE il."itemId" = r."itemId" AND il."companyId" = r."companyId"),
          CURRENT_DATE
        )
      FROM "itemCost" ic
      JOIN "item" i ON i."id" = ic."itemId"
      WHERE ic."itemId" = r."itemId"
        AND ic."companyId" = r."companyId";
    END IF;
  END LOOP;
END $$;
```

- [ ] **Step 2: Commit**

```bash
git add packages/database/supabase/migrations/20260504000001_cost-layers-backfill.sql
git commit -m "feat: backfill remainingQuantity on existing costLedger entries"
```

---

### Task 3: COGS Calculation Engine

**Files:**
- Create: `packages/database/supabase/functions/shared/calculate-cogs.ts`

- [ ] **Step 1: Create the COGS calculation engine**

This shared module is used by `post-shipment` (for SO shipments) and `post-sales-invoice` (for direct invoices). It supports all four costing methods and handles FIFO/LIFO layer consumption within a Kysely transaction.

```typescript
import { Transaction } from "kysely";
import { DB } from "../lib/database.ts";

export interface CostLayer {
  costLedgerId: string;
  quantityConsumed: number;
  unitCost: number;
}

export interface COGSResult {
  unitCost: number;
  totalCost: number;
  layersConsumed: CostLayer[];
}

export async function calculateCOGS(
  trx: Transaction<DB>,
  {
    itemId,
    quantity,
    companyId,
  }: {
    itemId: string;
    quantity: number;
    companyId: string;
  }
): Promise<COGSResult> {
  const itemCost = await trx
    .selectFrom("itemCost")
    .selectAll()
    .where("itemId", "=", itemId)
    .where("companyId", "=", companyId)
    .executeTakeFirstOrThrow();

  const costingMethod = itemCost.costingMethod;

  switch (costingMethod) {
    case "Standard": {
      const standardCost = Number(itemCost.standardCost ?? 0);
      return {
        unitCost: standardCost,
        totalCost: standardCost * quantity,
        layersConsumed: [],
      };
    }

    case "Average": {
      const unitCost = Number(itemCost.unitCost ?? 0);
      return {
        unitCost,
        totalCost: unitCost * quantity,
        layersConsumed: [],
      };
    }

    case "FIFO":
    case "LIFO": {
      const orderDirection = costingMethod === "FIFO" ? "asc" : "desc";

      const layers = await trx
        .selectFrom("costLedger")
        .selectAll()
        .where("itemId", "=", itemId)
        .where("companyId", "=", companyId)
        .where("remainingQuantity", ">", 0)
        .orderBy("postingDate", orderDirection)
        .orderBy("createdAt", orderDirection)
        .execute();

      let remainingToConsume = quantity;
      let totalCost = 0;
      const layersConsumed: CostLayer[] = [];

      for (const layer of layers) {
        if (remainingToConsume <= 0) break;

        const layerRemaining = Number(layer.remainingQuantity);
        const layerUnitCost =
          Number(layer.quantity) > 0
            ? Number(layer.cost) / Number(layer.quantity)
            : 0;

        const quantityFromLayer = Math.min(remainingToConsume, layerRemaining);
        const costFromLayer = quantityFromLayer * layerUnitCost;

        totalCost += costFromLayer;
        remainingToConsume -= quantityFromLayer;

        layersConsumed.push({
          costLedgerId: layer.id,
          quantityConsumed: quantityFromLayer,
          unitCost: layerUnitCost,
        });

        await trx
          .updateTable("costLedger")
          .set({
            remainingQuantity: layerRemaining - quantityFromLayer,
          })
          .where("id", "=", layer.id)
          .execute();
      }

      // Fallback: insufficient layers (negative inventory scenario)
      if (remainingToConsume > 0) {
        const fallbackUnitCost = Number(itemCost.unitCost ?? 0);
        totalCost += remainingToConsume * fallbackUnitCost;
      }

      const effectiveUnitCost = quantity > 0 ? totalCost / quantity : 0;

      return {
        unitCost: effectiveUnitCost,
        totalCost,
        layersConsumed,
      };
    }

    default:
      throw new Error(`Unsupported costing method: ${costingMethod}`);
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add packages/database/supabase/functions/shared/calculate-cogs.ts
git commit -m "feat: add shared COGS calculation engine for Standard/Average/FIFO/LIFO"
```

---

### Task 4: Add Journal Reference Helpers

**Files:**
- Modify: `packages/database/supabase/functions/lib/utils.ts:85-92`

- [ ] **Step 1: Add job and materialIssue references**

In `packages/database/supabase/functions/lib/utils.ts`, add two new reference generators to the `journalReference.to` object:

```typescript
export const journalReference = {
  to: {
    purchaseInvoice: (id: string) => `purchase-invoice:${id}`,
    receipt: (id: string) => `receipt:${id}`,
    salesInvoice: (id: string) => `sales-invoice:${id}`,
    shipment: (id: string) => `shipment:${id}`,
    job: (id: string) => `job:${id}`,
    materialIssue: (id: string) => `material-issue:${id}`,
  },
};
```

- [ ] **Step 2: Commit**

```bash
git add packages/database/supabase/functions/lib/utils.ts
git commit -m "feat: add job and materialIssue journal reference helpers"
```

---

### Task 5: Set `remainingQuantity` in `update-purchased-prices`

**Files:**
- Modify: `packages/database/supabase/functions/update-purchased-prices/index.ts:134-147`

- [ ] **Step 1: Add `remainingQuantity` to costLedger inserts**

In the `purchaseOrder` case of `update-purchased-prices/index.ts`, the costLedger inserts (around line 136) need `remainingQuantity` set to the line quantity:

Change the `.map` callback at line 136 from:

```typescript
.map((line) => ({
  itemLedgerType: "Purchase" as const,
  costLedgerType: "Direct Cost" as const,
  adjustment: false,
  documentType: "Purchase Order" as const,
  documentId: purchaseOrderId,
  itemId: line.itemId!,
  quantity: line.quantity,
  cost: line.quantity * line.unitPrice,
  supplierId,
  companyId,
}));
```

to:

```typescript
.map((line) => ({
  itemLedgerType: "Purchase" as const,
  costLedgerType: "Direct Cost" as const,
  adjustment: false,
  documentType: "Purchase Order" as const,
  documentId: purchaseOrderId,
  itemId: line.itemId!,
  quantity: line.quantity,
  cost: line.quantity * line.unitPrice,
  remainingQuantity: line.quantity,
  supplierId,
  companyId,
}));
```

- [ ] **Step 2: Also update the `purchaseInvoice` case**

Find the costLedger insert in the `purchaseInvoice` case (search for `costLedger` after the `purchaseInvoice` case around line 157). Add `remainingQuantity` there too.

- [ ] **Step 3: Commit**

```bash
git add packages/database/supabase/functions/update-purchased-prices/index.ts
git commit -m "feat: set remainingQuantity on costLedger entries in update-purchased-prices"
```

---

### Task 6: Add Journal Entries to `post-shipment` (Sales Order Case)

**Files:**
- Modify: `packages/database/supabase/functions/post-shipment/index.ts`

This is the largest task. The Sales Order case currently only creates itemLedger entries (lines 142-813). We need to add: fetching accounting prerequisites, COGS calculation via the engine, journal line construction, dimension attachment, and costLedger entry creation.

- [ ] **Step 1: Add imports**

At the top of `post-shipment/index.ts`, add the new imports after the existing ones (line 8):

```typescript
import { isInternalUser } from "../lib/flags.ts";
import { credit, debit, journalReference } from "../lib/utils.ts";
import { getCurrentAccountingPeriod } from "../shared/get-accounting-period.ts";
import { getNextSequence } from "../shared/get-next-sequence.ts";
import { getDefaultPostingGroup } from "../shared/get-posting-group.ts";
import { calculateCOGS } from "../shared/calculate-cogs.ts";
import { nanoid } from "https://deno.land/x/nanoid@v3.0.0/mod.ts";
```

- [ ] **Step 2: Fetch accounting prerequisites**

Inside the `case "Sales Order"` block, after the `customer` fetch (around line 141), add fetches for `isInternal`, `accountDefaults`, `companyGroupId`, and `dimensions`:

```typescript
const [companyRecord, isInternal] = await Promise.all([
  client
    .from("company")
    .select("companyGroupId")
    .eq("id", companyId)
    .single(),
  isInternalUser(client, userId),
]);
if (companyRecord.error) throw new Error("Failed to fetch company");
const companyGroupId = companyRecord.data.companyGroupId;

const accountDefaults = isInternal
  ? await getDefaultPostingGroup(client, companyId)
  : null;
if (isInternal && (accountDefaults?.error || !accountDefaults?.data)) {
  throw new Error("Error getting account defaults");
}

const dimensions = isInternal
  ? await client
      .from("dimension")
      .select("id, entityType")
      .eq("companyGroupId", companyGroupId)
      .eq("active", true)
      .in("entityType", [
        "CustomerType",
        "ItemPostingGroup",
        "Location",
        "CostCenter",
      ])
  : null;

const dimensionMap = new Map<string, string>();
if (dimensions?.data) {
  for (const dim of dimensions.data) {
    if (dim.entityType) dimensionMap.set(dim.entityType, dim.id);
  }
}
```

- [ ] **Step 3: Add journal line and dimension tracking arrays**

After the existing `itemLedgerInserts` array declaration (line 142), add:

```typescript
const journalLineInserts: Omit<
  Database["public"]["Tables"]["journalLine"]["Insert"],
  "journalId"
>[] = [];

const journalLineDimensionsMeta: {
  customerTypeId: string | null;
  itemPostingGroupId: string | null;
  locationId: string | null;
  costCenterId: string | null;
}[] = [];
```

- [ ] **Step 4: Add COGS journal entries inside the shipment line loop**

Inside the `for await (const shipmentLine of shipmentLines.data)` loop, after each itemLedger push block (the Inventory, Batch, and Serial tracking sections around lines 275-343), add COGS journal entry logic. Place this before the closing `}` of the loop body (before line 344):

```typescript
// COGS journal entries for this shipment line
if (
  isInternal &&
  accountDefaults?.data &&
  shipmentLine.itemId &&
  shipmentLine.shippedQuantity > 0 &&
  itemTrackingType !== "Non-Inventory"
) {
  const itemPostingGroupId =
    itemCosts.data.find(
      (cost) => cost.itemId === shipmentLine.itemId
    )?.itemPostingGroupId ?? null;

  const salesOrderLine = salesOrderLines.data.find(
    (sol) => sol.id === shipmentLine.lineId
  );

  const journalLineReference = nanoid();

  // DR COGS / CR Inventory — actual cost from COGS engine
  // (calculated later inside the transaction; placeholder amounts replaced)
  journalLineInserts.push({
    accountId: accountDefaults.data.costOfGoodsSoldAccount,
    description: "Cost of Goods Sold",
    amount: 0, // replaced in transaction
    quantity: shippedQuantity,
    documentType: "Shipment",
    documentId: shipment.data?.id,
    externalDocumentId: salesOrder.data?.customerReference ?? undefined,
    documentLineReference: journalReference.to.shipment(
      shipmentLine.id
    ),
    journalLineReference,
    companyId,
  });

  journalLineInserts.push({
    accountId: accountDefaults.data.inventoryAccount,
    description: "Inventory Account",
    amount: 0, // replaced in transaction
    quantity: shippedQuantity,
    documentType: "Shipment",
    documentId: shipment.data?.id,
    externalDocumentId: salesOrder.data?.customerReference ?? undefined,
    documentLineReference: journalReference.to.shipment(
      shipmentLine.id
    ),
    journalLineReference,
    companyId,
  });

  // Track dimension metadata for these two journal lines
  for (let i = 0; i < 2; i++) {
    journalLineDimensionsMeta.push({
      customerTypeId: customer.data.customerTypeId ?? null,
      itemPostingGroupId,
      locationId: shipmentLine.locationId ?? locationId ?? null,
      costCenterId: salesOrderLine?.costCenterId ?? null,
    });
  }
}
```

- [ ] **Step 5: Calculate COGS and insert journal entries inside the transaction**

Inside the `await db.transaction().execute(async (trx) => {` block (starts around line 480), after all the existing updates (salesOrderLine updates, salesOrder status update, shipment status update, tracked entity operations, itemLedger inserts, job updates — ending around line 812), add the COGS calculation and journal entry insertion:

```typescript
// Calculate COGS and create journal entries
if (isInternal && journalLineInserts.length > 0) {
  // Group journal lines by itemId to batch COGS calculations
  const itemShipmentQuantities = new Map<
    string,
    { totalQuantity: number; lineIndices: number[] }
  >();

  for (let i = 0; i < journalLineInserts.length; i += 2) {
    const jl = journalLineInserts[i];
    // Find the shipment line that owns this journal line pair
    const ref = jl.documentLineReference;
    const shipmentLine = shipmentLines.data.find(
      (sl) => ref === journalReference.to.shipment(sl.id)
    );
    if (!shipmentLine?.itemId) continue;

    const existing = itemShipmentQuantities.get(shipmentLine.itemId);
    if (existing) {
      existing.totalQuantity += jl.quantity ?? 0;
      existing.lineIndices.push(i);
    } else {
      itemShipmentQuantities.set(shipmentLine.itemId, {
        totalQuantity: jl.quantity ?? 0,
        lineIndices: [i],
      });
    }
  }

  // Calculate COGS for each item and fill in amounts
  for (const [itemId, info] of itemShipmentQuantities) {
    const cogsResult = await calculateCOGS(trx, {
      itemId,
      quantity: info.totalQuantity,
      companyId,
    });

    // Distribute cost proportionally across lines for this item
    let costAssigned = 0;
    for (let idx = 0; idx < info.lineIndices.length; idx++) {
      const jlIdx = info.lineIndices[idx];
      const lineQty = journalLineInserts[jlIdx].quantity ?? 0;
      const lineCost =
        idx === info.lineIndices.length - 1
          ? cogsResult.totalCost - costAssigned // last line gets remainder to avoid rounding
          : (lineQty / info.totalQuantity) * cogsResult.totalCost;

      costAssigned += lineCost;

      // COGS debit line
      journalLineInserts[jlIdx].amount = debit("expense", lineCost);
      // Inventory credit line
      journalLineInserts[jlIdx + 1].amount = credit("asset", lineCost);
    }

    // Write costLedger entry for the sale
    await trx
      .insertInto("costLedger")
      .values({
        itemLedgerType: "Sale",
        costLedgerType: "Direct Cost",
        adjustment: false,
        documentType: "Sales Shipment",
        documentId: shipment.data?.id ?? "",
        itemId,
        quantity: -info.totalQuantity,
        cost: -cogsResult.totalCost,
        remainingQuantity: 0,
        companyId,
      })
      .execute();
  }

  // Create journal entry
  const accountingPeriodId = await getCurrentAccountingPeriod(
    client,
    companyId,
    db
  );

  const journalEntryId = await getNextSequence(
    trx,
    "journalEntry",
    companyId
  );

  const journalResult = await trx
    .insertInto("journal")
    .values({
      journalEntryId,
      accountingPeriodId,
      description: `Sales Shipment ${shipment.data.shipmentId}`,
      postingDate: today,
      companyId,
      sourceType: "Sales Shipment",
      status: "Posted",
      postedAt: new Date().toISOString(),
      postedBy: userId,
      createdBy: userId,
    })
    .returning(["id"])
    .executeTakeFirstOrThrow();

  const journalLineResults = await trx
    .insertInto("journalLine")
    .values(
      journalLineInserts.map((line) => ({
        ...line,
        journalId: journalResult.id,
      }))
    )
    .returning(["id"])
    .execute();

  // Insert dimensions
  if (dimensionMap.size > 0) {
    const journalLineDimensionInserts: {
      journalLineId: string;
      dimensionId: string;
      valueId: string;
      companyId: string;
    }[] = [];

    journalLineResults.forEach((jl, index) => {
      const meta = journalLineDimensionsMeta[index];
      if (!meta) return;

      if (
        meta.customerTypeId &&
        dimensionMap.has("CustomerType")
      ) {
        journalLineDimensionInserts.push({
          journalLineId: jl.id,
          dimensionId: dimensionMap.get("CustomerType")!,
          valueId: meta.customerTypeId,
          companyId,
        });
      }
      if (
        meta.itemPostingGroupId &&
        dimensionMap.has("ItemPostingGroup")
      ) {
        journalLineDimensionInserts.push({
          journalLineId: jl.id,
          dimensionId: dimensionMap.get("ItemPostingGroup")!,
          valueId: meta.itemPostingGroupId,
          companyId,
        });
      }
      if (meta.locationId && dimensionMap.has("Location")) {
        journalLineDimensionInserts.push({
          journalLineId: jl.id,
          dimensionId: dimensionMap.get("Location")!,
          valueId: meta.locationId,
          companyId,
        });
      }
      if (meta.costCenterId && dimensionMap.has("CostCenter")) {
        journalLineDimensionInserts.push({
          journalLineId: jl.id,
          dimensionId: dimensionMap.get("CostCenter")!,
          valueId: meta.costCenterId,
          companyId,
        });
      }
    });

    if (journalLineDimensionInserts.length > 0) {
      await trx
        .insertInto("journalLineDimension")
        .values(journalLineDimensionInserts)
        .execute();
    }
  }
}
```

- [ ] **Step 6: Commit**

```bash
git add packages/database/supabase/functions/post-shipment/index.ts
git commit -m "feat: add COGS journal entries, cost layer consumption, and dimensions to post-shipment"
```

---

### Task 7: Fix `post-sales-invoice` — Remove COGS When Shipment Exists, Fix Direct Invoice COGS, Add Dimensions

**Files:**
- Modify: `packages/database/supabase/functions/post-sales-invoice/index.ts`

The current code has two problems:
1. When `salesOrderLineId !== null` (SO-linked), it posts COGS using the selling price (lines 456-503). Since COGS is now posted at shipment, these entries must be removed.
2. When `salesOrderLineId === null` (direct invoice), it also uses selling price (lines 334-365). These need to use the COGS calculation engine instead.
3. No dimensions are attached to any journal lines.

- [ ] **Step 1: Add imports**

After the existing imports at the top, add:

```typescript
import { calculateCOGS } from "../shared/calculate-cogs.ts";
```

- [ ] **Step 2: Add itemCost costingMethod to the fetch**

Change the `itemCosts` select at line 135 from:

```typescript
client
  .from("itemCost")
  .select("itemId, itemPostingGroupId")
  .in("itemId", itemIds),
```

to:

```typescript
client
  .from("itemCost")
  .select("itemId, itemPostingGroupId, costingMethod")
  .in("itemId", itemIds),
```

- [ ] **Step 3: Fetch dimensions**

After the `accountDefaults` fetch (around line 237), add:

```typescript
const companyGroupIdForDimensions = companyGroupId;
const dimensions = isInternal
  ? await client
      .from("dimension")
      .select("id, entityType")
      .eq("companyGroupId", companyGroupIdForDimensions)
      .eq("active", true)
      .in("entityType", [
        "CustomerType",
        "ItemPostingGroup",
        "Location",
        "CostCenter",
      ])
  : null;

const dimensionMap = new Map<string, string>();
if (dimensions?.data) {
  for (const dim of dimensions.data) {
    if (dim.entityType) dimensionMap.set(dim.entityType, dim.id);
  }
}

const journalLineDimensionsMeta: {
  customerTypeId: string | null;
  itemPostingGroupId: string | null;
  locationId: string | null;
  costCenterId: string | null;
}[] = [];
```

- [ ] **Step 4: Remove COGS from SO-linked invoice lines**

In the `else` block (SO-linked lines, starting around line 409), remove the COGS/Inventory journal entries (lines 456-503). Keep ONLY the AR debit and Sales Revenue credit entries.

The `else` block should become:

```typescript
else {
  if (isInternal && accountDefaults?.data) {
    journalLineReference = nanoid();

    // Credit the sales account (Revenue)
    journalLineInserts.push({
      accountId: accountDefaults.data.salesAccount,
      description: "Sales Account",
      amount: credit(
        "revenue",
        totalLineCostWithWeightedShipping
      ),
      quantity: invoiceLineQuantityInInventoryUnit,
      documentType: "Invoice",
      documentId: salesInvoice.data?.id,
      externalDocumentId: salesInvoice.data?.customerReference,
      documentLineReference: invoiceLine.salesOrderLineId
        ? journalReference.to.salesInvoice(
            invoiceLine.salesOrderLineId
          )
        : null,
      journalLineReference,
      companyId,
    });

    // Debit accounts receivable
    journalLineInserts.push({
      accountId: receivablesAccountId,
      description: isIntercompany
        ? "IC Receivables"
        : "Accounts Receivable",
      amount: debit("asset", totalLineCostWithWeightedShipping),
      quantity: invoiceLineQuantityInInventoryUnit,
      documentType: "Invoice",
      documentId: salesInvoice.data?.id,
      externalDocumentId: salesInvoice.data?.customerReference,
      documentLineReference: invoiceLine.salesOrderLineId
        ? journalReference.to.salesInvoice(
            invoiceLine.salesOrderLineId
          )
        : null,
      journalLineReference,
      intercompanyPartnerId,
      companyId,
    });

    // Track dimension metadata for AR + Revenue lines
    const itemPostingGroupId =
      itemCosts.data.find(
        (cost) => cost.itemId === invoiceLine.itemId
      )?.itemPostingGroupId ?? null;

    const salesOrder = salesOrders.data?.find(
      (so) =>
        so.salesOrderId ===
        salesOrderLines.find(
          (sol) => sol.id === invoiceLine.salesOrderLineId
        )?.salesOrderId
    );

    for (let i = 0; i < 2; i++) {
      journalLineDimensionsMeta.push({
        customerTypeId: customer.data.customerTypeId ?? null,
        itemPostingGroupId,
        locationId: invoiceLine.locationId ?? null,
        costCenterId: null,
      });
    }
  }
}
```

- [ ] **Step 5: Fix direct invoice COGS to use COGS engine**

In the direct invoice block (where `salesOrderLineId === null`, around lines 293-407), the COGS/Inventory entries at lines 334-365 currently use `totalLineCostWithWeightedShipping` (the selling price). These need to be deferred to the transaction where we can call `calculateCOGS`. 

Replace the COGS journal line pushes with placeholders that will be filled in during the transaction (same pattern as Task 6 for post-shipment). Mark these entries with a flag or use amount = 0 and fill them in inside the `db.transaction()` block.

After the direct invoice's AR/Revenue entries, replace the COGS block:

```typescript
if (itemTrackingType === "Inventory") {
  const cogsJournalLineReference = nanoid();

  // Placeholder — amounts filled in during transaction via calculateCOGS
  journalLineInserts.push({
    accountId: accountDefaults.data.costOfGoodsSoldAccount,
    description: "Cost of Goods Sold",
    amount: 0,
    quantity: invoiceLineQuantityInInventoryUnit,
    documentType: "Invoice",
    documentId: salesInvoice.data?.id,
    externalDocumentId:
      salesInvoice.data?.customerReference,
    journalLineReference: cogsJournalLineReference,
    companyId,
  });

  journalLineInserts.push({
    accountId: accountDefaults.data.inventoryAccount,
    description: "Inventory Account",
    amount: 0,
    quantity: invoiceLineQuantityInInventoryUnit,
    documentType: "Invoice",
    documentId: salesInvoice.data?.id,
    externalDocumentId:
      salesInvoice.data?.customerReference,
    journalLineReference: cogsJournalLineReference,
    companyId,
  });

  // Track dimensions for COGS lines
  const lineItemPostingGroupId =
    itemCosts.data.find(
      (cost) => cost.itemId === invoiceLine.itemId
    )?.itemPostingGroupId ?? null;

  for (let i = 0; i < 2; i++) {
    journalLineDimensionsMeta.push({
      customerTypeId: customer.data.customerTypeId ?? null,
      itemPostingGroupId: lineItemPostingGroupId,
      locationId: invoiceLine.locationId ?? null,
      costCenterId: null,
    });
  }
}
```

Then inside the `db.transaction()` block (around line 524), before the journal insertion, calculate COGS for direct invoice lines:

```typescript
// Calculate COGS for direct invoice items (no sales order)
const directInvoiceItems = salesInvoiceLines.data.filter(
  (line) => line.salesOrderLineId === null && line.itemId
);

for (const invoiceLine of directInvoiceItems) {
  if (!invoiceLine.itemId) continue;

  const itemTrackingType =
    items.data.find((item) => item.id === invoiceLine.itemId)
      ?.itemTrackingType ?? "Inventory";

  if (itemTrackingType !== "Inventory") continue;

  const cogsResult = await calculateCOGS(trx, {
    itemId: invoiceLine.itemId,
    quantity: invoiceLine.quantity,
    companyId,
  });

  // Find the placeholder COGS journal lines for this item and fill amounts
  for (let i = 0; i < journalLineInserts.length; i++) {
    const jl = journalLineInserts[i];
    if (
      jl.description === "Cost of Goods Sold" &&
      jl.amount === 0 &&
      jl.quantity === invoiceLine.quantity
    ) {
      journalLineInserts[i].amount = debit(
        "expense",
        cogsResult.totalCost
      );
      // The next line should be the Inventory credit
      if (i + 1 < journalLineInserts.length) {
        journalLineInserts[i + 1].amount = credit(
          "asset",
          cogsResult.totalCost
        );
      }

      // Write costLedger entry for the sale
      await trx
        .insertInto("costLedger")
        .values({
          itemLedgerType: "Sale",
          costLedgerType: "Direct Cost",
          adjustment: false,
          documentType: "Sales Shipment",
          documentId: salesInvoice.data?.id ?? "",
          itemId: invoiceLine.itemId,
          quantity: -invoiceLine.quantity,
          cost: -cogsResult.totalCost,
          remainingQuantity: 0,
          companyId,
        })
        .execute();

      break;
    }
  }
}
```

- [ ] **Step 6: Add dimension insertion after journal line creation**

Inside the transaction, after the `journalLineResults` insert (find the existing journal line insert), add dimension insertion using the same pattern as post-receipt:

```typescript
if (dimensionMap.size > 0) {
  const journalLineDimensionInserts: {
    journalLineId: string;
    dimensionId: string;
    valueId: string;
    companyId: string;
  }[] = [];

  journalLineResults.forEach((jl, index) => {
    const meta = journalLineDimensionsMeta[index];
    if (!meta) return;

    if (meta.customerTypeId && dimensionMap.has("CustomerType")) {
      journalLineDimensionInserts.push({
        journalLineId: jl.id,
        dimensionId: dimensionMap.get("CustomerType")!,
        valueId: meta.customerTypeId,
        companyId,
      });
    }
    if (meta.itemPostingGroupId && dimensionMap.has("ItemPostingGroup")) {
      journalLineDimensionInserts.push({
        journalLineId: jl.id,
        dimensionId: dimensionMap.get("ItemPostingGroup")!,
        valueId: meta.itemPostingGroupId,
        companyId,
      });
    }
    if (meta.locationId && dimensionMap.has("Location")) {
      journalLineDimensionInserts.push({
        journalLineId: jl.id,
        dimensionId: dimensionMap.get("Location")!,
        valueId: meta.locationId,
        companyId,
      });
    }
    if (meta.costCenterId && dimensionMap.has("CostCenter")) {
      journalLineDimensionInserts.push({
        journalLineId: jl.id,
        dimensionId: dimensionMap.get("CostCenter")!,
        valueId: meta.costCenterId,
        companyId,
      });
    }
  });

  if (journalLineDimensionInserts.length > 0) {
    await trx
      .insertInto("journalLineDimension")
      .values(journalLineDimensionInserts)
      .execute();
  }
}
```

- [ ] **Step 7: Commit**

```bash
git add packages/database/supabase/functions/post-sales-invoice/index.ts
git commit -m "feat: remove COGS from SO-linked invoices, fix direct invoice COGS, add dimensions"
```

---

### Task 8: WIP Journal Entries on Material Issuance

**Files:**
- Modify: `packages/database/supabase/functions/issue/index.ts`

The `issueJobOperationMaterials` function (lines 100-296) creates itemLedger entries for material consumption but no journal entries. We need to add: DR WIP / CR Raw Material Inventory for each issued material.

- [ ] **Step 1: Add imports**

At the top of `issue/index.ts`, add:

```typescript
import { credit, debit, journalReference } from "../lib/utils.ts";
import { isInternalUser } from "../lib/flags.ts";
import { getCurrentAccountingPeriod } from "../shared/get-accounting-period.ts";
import { getNextSequence } from "../shared/get-next-sequence.ts";
import { getDefaultPostingGroup } from "../shared/get-posting-group.ts";
import { calculateCOGS } from "../shared/calculate-cogs.ts";
import { nanoid } from "https://deno.land/x/nanoid@v3.0.0/mod.ts";
```

- [ ] **Step 2: Add accounting parameters to `issueJobOperationMaterials`**

Expand the function signature to accept `isInternal` and return cost info:

```typescript
async function issueJobOperationMaterials(
  trx: Transaction<DB>,
  {
    jobOperationId,
    quantity,
    companyId,
    userId,
    isInternal,
    accountDefaults,
    dimensionMap,
    client,
    db,
  }: {
    jobOperationId: string;
    quantity: number;
    companyId: string;
    userId: string;
    isInternal: boolean;
    accountDefaults: any;
    dimensionMap: Map<string, string>;
    client: any;
    db: any;
  }
)
```

- [ ] **Step 3: Add WIP journal entries inside the material issuance loop**

After the `itemLedgerInserts` are built and inserted (around line 283), add:

```typescript
// WIP journal entries for material issuance
if (isInternal && accountDefaults?.data && itemLedgerInserts.length > 0) {
  const journalLineInserts: {
    accountId: string;
    description: string;
    amount: number;
    quantity: number;
    documentType: string;
    documentId: string;
    documentLineReference: string;
    journalLineReference: string;
    companyId: string;
  }[] = [];

  const journalLineDimensionsMeta: {
    itemPostingGroupId: string | null;
    locationId: string | null;
    costCenterId: string | null;
  }[] = [];

  // Get the finished good's itemCost for dimension
  const finishedGoodJob = await trx
    .selectFrom("job")
    .where("id", "=", jobId)
    .select(["itemId", "locationId"])
    .executeTakeFirst();

  const finishedGoodItemCost = finishedGoodJob?.itemId
    ? await trx
        .selectFrom("itemCost")
        .where("itemId", "=", finishedGoodJob.itemId)
        .where("companyId", "=", companyId)
        .select("itemPostingGroupId")
        .executeTakeFirst()
    : null;

  for (const ledger of itemLedgerInserts) {
    const materialQuantity = Math.abs(Number(ledger.quantity));
    if (materialQuantity === 0) continue;

    // Calculate the cost of the issued material
    const cogsResult = await calculateCOGS(trx, {
      itemId: ledger.itemId,
      quantity: materialQuantity,
      companyId,
    });

    const journalLineReference = nanoid();

    // DR WIP
    journalLineInserts.push({
      accountId: accountDefaults.data.workInProgressAccount,
      description: "WIP Account",
      amount: debit("asset", cogsResult.totalCost),
      quantity: materialQuantity,
      documentType: "Job Consumption",
      documentId: jobId,
      documentLineReference: journalReference.to.materialIssue(
        jobOperationId
      ),
      journalLineReference,
      companyId,
    });

    // CR Raw Material Inventory
    journalLineInserts.push({
      accountId: accountDefaults.data.inventoryAccount,
      description: "Inventory Account",
      amount: credit("asset", cogsResult.totalCost),
      quantity: materialQuantity,
      documentType: "Job Consumption",
      documentId: jobId,
      documentLineReference: journalReference.to.materialIssue(
        jobOperationId
      ),
      journalLineReference,
      companyId,
    });

    // Write costLedger entry for the consumption
    await trx
      .insertInto("costLedger")
      .values({
        itemLedgerType: "Consumption",
        costLedgerType: "Direct Cost",
        adjustment: false,
        documentType: "Job Consumption",
        documentId: jobId,
        itemId: ledger.itemId,
        quantity: -materialQuantity,
        cost: -cogsResult.totalCost,
        remainingQuantity: 0,
        companyId,
      })
      .execute();

    // Dimension metadata
    for (let i = 0; i < 2; i++) {
      journalLineDimensionsMeta.push({
        itemPostingGroupId:
          finishedGoodItemCost?.itemPostingGroupId ?? null,
        locationId: finishedGoodJob?.locationId ?? null,
        costCenterId: null,
      });
    }
  }

  if (journalLineInserts.length > 0) {
    const accountingPeriodId = await getCurrentAccountingPeriod(
      client,
      companyId,
      db
    );

    const journalEntryId = await getNextSequence(
      trx,
      "journalEntry",
      companyId
    );

    const journalResult = await trx
      .insertInto("journal")
      .values({
        journalEntryId,
        accountingPeriodId,
        description: `Material Issue to Job ${jobId}`,
        postingDate: new Date().toISOString().slice(0, 10),
        companyId,
        sourceType: "Job Consumption",
        status: "Posted",
        postedAt: new Date().toISOString(),
        postedBy: userId,
        createdBy: userId,
      })
      .returning(["id"])
      .executeTakeFirstOrThrow();

    const journalLineResults = await trx
      .insertInto("journalLine")
      .values(
        journalLineInserts.map((line) => ({
          ...line,
          journalId: journalResult.id,
        }))
      )
      .returning(["id"])
      .execute();

    if (dimensionMap.size > 0) {
      const dimensionInserts: {
        journalLineId: string;
        dimensionId: string;
        valueId: string;
        companyId: string;
      }[] = [];

      journalLineResults.forEach((jl, index) => {
        const meta = journalLineDimensionsMeta[index];
        if (!meta) return;

        if (
          meta.itemPostingGroupId &&
          dimensionMap.has("ItemPostingGroup")
        ) {
          dimensionInserts.push({
            journalLineId: jl.id,
            dimensionId: dimensionMap.get("ItemPostingGroup")!,
            valueId: meta.itemPostingGroupId,
            companyId,
          });
        }
        if (meta.locationId && dimensionMap.has("Location")) {
          dimensionInserts.push({
            journalLineId: jl.id,
            dimensionId: dimensionMap.get("Location")!,
            valueId: meta.locationId,
            companyId,
          });
        }
        if (meta.costCenterId && dimensionMap.has("CostCenter")) {
          dimensionInserts.push({
            journalLineId: jl.id,
            dimensionId: dimensionMap.get("CostCenter")!,
            valueId: meta.costCenterId,
            companyId,
          });
        }
      });

      if (dimensionInserts.length > 0) {
        await trx
          .insertInto("journalLineDimension")
          .values(dimensionInserts)
          .execute();
      }
    }
  }
}
```

- [ ] **Step 4: Update all callers of `issueJobOperationMaterials`**

Search for all call sites of `issueJobOperationMaterials` in `issue/index.ts`. Each one needs the new parameters. The `jobOperation` case (around line 624) calls it inside a transaction:

```typescript
case "jobOperation": {
  const { id, companyId, quantity, userId } = validatedPayload;

  const client = await getSupabaseServiceRole(
    req.headers.get("Authorization"),
    req.headers.get("carbon-key") ?? "",
    companyId
  );

  const [isInternal, companyRecord] = await Promise.all([
    isInternalUser(client, userId),
    client
      .from("company")
      .select("companyGroupId")
      .eq("id", companyId)
      .single(),
  ]);
  if (companyRecord.error) throw new Error("Failed to fetch company");

  const accountDefaults = isInternal
    ? await getDefaultPostingGroup(client, companyId)
    : null;
  if (isInternal && (accountDefaults?.error || !accountDefaults?.data)) {
    throw new Error("Error getting account defaults");
  }

  const dimensions = isInternal
    ? await client
        .from("dimension")
        .select("id, entityType")
        .eq("companyGroupId", companyRecord.data.companyGroupId)
        .eq("active", true)
        .in("entityType", ["ItemPostingGroup", "Location", "CostCenter"])
    : null;

  const dimensionMap = new Map<string, string>();
  if (dimensions?.data) {
    for (const dim of dimensions.data) {
      if (dim.entityType) dimensionMap.set(dim.entityType, dim.id);
    }
  }

  await db.transaction().execute(async (trx) => {
    await issueJobOperationMaterials(trx, {
      jobOperationId: id,
      quantity,
      companyId,
      userId,
      isInternal,
      accountDefaults: accountDefaults?.data ? accountDefaults : null,
      dimensionMap,
      client,
      db,
    });
  });

  break;
}
```

Do the same for all other call sites (e.g., `jobOperationBatchComplete`, trigger-based calls).

- [ ] **Step 5: Commit**

```bash
git add packages/database/supabase/functions/issue/index.ts
git commit -m "feat: add WIP journal entries and costLedger consumption on material issuance"
```

---

### Task 9: Job Completion — FG Receipt, CostLedger, WIP Discharge

**Files:**
- Modify: `packages/database/supabase/functions/issue/index.ts` (the `jobCompleteInventory` case, lines 473-620)

On job completion, we need to:
1. Calculate total accumulated WIP cost (sum of all WIP debits for this job)
2. Create journal entries: DR Finished Goods Inventory / CR WIP
3. Write a costLedger entry for the finished good (with `remainingQuantity`)
4. Update `itemCost.unitCost` for Average cost items

- [ ] **Step 1: Add accounting fetches to `jobCompleteInventory` case**

Inside the `jobCompleteInventory` case (starts around line 473), after the `client` initialization (line 484), add:

```typescript
const [isInternal, companyRecord] = await Promise.all([
  isInternalUser(client, userId),
  client
    .from("company")
    .select("companyGroupId")
    .eq("id", companyId)
    .single(),
]);
if (companyRecord.error) throw new Error("Failed to fetch company");

const accountDefaults = isInternal
  ? await getDefaultPostingGroup(client, companyId)
  : null;
if (isInternal && (accountDefaults?.error || !accountDefaults?.data)) {
  throw new Error("Error getting account defaults");
}

const dimensions = isInternal
  ? await client
      .from("dimension")
      .select("id, entityType")
      .eq("companyGroupId", companyRecord.data.companyGroupId)
      .eq("active", true)
      .in("entityType", ["ItemPostingGroup", "Location", "CostCenter"])
  : null;

const dimensionMap = new Map<string, string>();
if (dimensions?.data) {
  for (const dim of dimensions.data) {
    if (dim.entityType) dimensionMap.set(dim.entityType, dim.id);
  }
}
```

- [ ] **Step 2: Add WIP discharge and costLedger entry inside the transaction**

Inside the `db.transaction()` block, after the itemLedger inserts (around line 617), add:

```typescript
// WIP discharge: DR FG Inventory / CR WIP
if (isInternal && accountDefaults?.data) {
  // Calculate accumulated WIP cost for this job
  // Sum all journal lines where documentId = jobId and accountId = WIP account (debit side)
  const wipEntries = await trx
    .selectFrom("journalLine")
    .innerJoin("journal", "journal.id", "journalLine.journalId")
    .select((eb) => eb.fn.sum("journalLine.amount").as("totalWip"))
    .where("journalLine.accountId", "=", accountDefaults.data!.workInProgressAccount)
    .where("journalLine.documentId", "=", jobId)
    .where("journal.companyId", "=", companyId)
    .executeTakeFirst();

  const accumulatedWipCost = Math.abs(Number(wipEntries?.totalWip ?? 0));

  if (accumulatedWipCost > 0) {
    const today = new Date().toISOString().slice(0, 10);
    const journalLineReference = nanoid();

    const journalLineInserts = [
      {
        accountId: accountDefaults.data.inventoryAccount,
        description: "Finished Goods Inventory",
        amount: debit("asset", accumulatedWipCost),
        quantity: quantityComplete,
        documentType: "Job Receipt",
        documentId: jobId,
        documentLineReference: journalReference.to.job(jobId),
        journalLineReference,
        companyId,
      },
      {
        accountId: accountDefaults.data.workInProgressAccount,
        description: "WIP Account",
        amount: credit("asset", accumulatedWipCost),
        quantity: quantityComplete,
        documentType: "Job Receipt",
        documentId: jobId,
        documentLineReference: journalReference.to.job(jobId),
        journalLineReference,
        companyId,
      },
    ];

    const accountingPeriodId = await getCurrentAccountingPeriod(
      client,
      companyId,
      db
    );

    const journalEntryId = await getNextSequence(
      trx,
      "journalEntry",
      companyId
    );

    const journalResult = await trx
      .insertInto("journal")
      .values({
        journalEntryId,
        accountingPeriodId,
        description: `Job Completion ${jobId}`,
        postingDate: today,
        companyId,
        sourceType: "Job Receipt",
        status: "Posted",
        postedAt: new Date().toISOString(),
        postedBy: userId,
        createdBy: userId,
      })
      .returning(["id"])
      .executeTakeFirstOrThrow();

    const journalLineResults = await trx
      .insertInto("journalLine")
      .values(
        journalLineInserts.map((line) => ({
          ...line,
          journalId: journalResult.id,
        }))
      )
      .returning(["id"])
      .execute();

    // Write costLedger entry for finished good
    await trx
      .insertInto("costLedger")
      .values({
        itemLedgerType: "Output",
        costLedgerType: "Direct Cost",
        adjustment: false,
        documentType: "Job Receipt",
        documentId: jobId,
        itemId: job.itemId!,
        quantity: quantityReceivedToInventory,
        cost: accumulatedWipCost,
        remainingQuantity: quantityReceivedToInventory,
        companyId,
      })
      .execute();

    // Update itemCost.unitCost for Average cost items
    const finishedItemCost = await trx
      .selectFrom("itemCost")
      .selectAll()
      .where("itemId", "=", job.itemId!)
      .where("companyId", "=", companyId)
      .executeTakeFirst();

    if (finishedItemCost?.costingMethod === "Average") {
      // Weighted average: (existing value + new value) / (existing qty + new qty)
      const existingOnHand = await trx
        .selectFrom("itemLedger")
        .select((eb) => eb.fn.sum("quantity").as("quantity"))
        .where("itemId", "=", job.itemId!)
        .where("companyId", "=", companyId)
        .executeTakeFirst();

      const existingQty = Number(existingOnHand?.quantity ?? 0);
      const existingValue =
        existingQty * Number(finishedItemCost.unitCost ?? 0);
      const newValue = accumulatedWipCost;
      const newQty = quantityReceivedToInventory;
      const totalQty = existingQty + newQty;

      if (totalQty > 0) {
        const newUnitCost = (existingValue + newValue) / totalQty;
        await trx
          .updateTable("itemCost")
          .set({ unitCost: newUnitCost })
          .where("itemId", "=", job.itemId!)
          .where("companyId", "=", companyId)
          .execute();
      }
    }

    // Insert dimensions
    if (dimensionMap.size > 0) {
      const finishedGoodItemCost = await trx
        .selectFrom("itemCost")
        .where("itemId", "=", job.itemId!)
        .where("companyId", "=", companyId)
        .select("itemPostingGroupId")
        .executeTakeFirst();

      const jobRecord = await trx
        .selectFrom("job")
        .where("id", "=", jobId)
        .select(["locationId"])
        .executeTakeFirst();

      const dimensionInserts: {
        journalLineId: string;
        dimensionId: string;
        valueId: string;
        companyId: string;
      }[] = [];

      journalLineResults.forEach((jl) => {
        if (
          finishedGoodItemCost?.itemPostingGroupId &&
          dimensionMap.has("ItemPostingGroup")
        ) {
          dimensionInserts.push({
            journalLineId: jl.id,
            dimensionId: dimensionMap.get("ItemPostingGroup")!,
            valueId: finishedGoodItemCost.itemPostingGroupId,
            companyId,
          });
        }
        if (jobRecord?.locationId && dimensionMap.has("Location")) {
          dimensionInserts.push({
            journalLineId: jl.id,
            dimensionId: dimensionMap.get("Location")!,
            valueId: jobRecord.locationId,
            companyId,
          });
        }
      });

      if (dimensionInserts.length > 0) {
        await trx
          .insertInto("journalLineDimension")
          .values(dimensionInserts)
          .execute();
      }
    }
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add packages/database/supabase/functions/issue/index.ts
git commit -m "feat: add WIP discharge journal entries and costLedger on job completion"
```

---

### Task 10: WIP Journal Entries on Labor/Machine Time

**Files:**
- Create: `packages/database/supabase/functions/post-production-event/index.ts`
- Modify: `apps/erp/app/routes/x+/job+/$jobId.events.new.tsx`
- Modify: `apps/erp/app/routes/x+/job+/$jobId.events.$id.tsx`
- Modify: `apps/mes/app/services/operations.service.ts`

Production events are created via Supabase client (not Kysely transactions) in two places:
- `apps/erp/app/modules/production/production.service.ts:2054` — `upsertProductionEvent`
- `apps/mes/app/services/operations.service.ts:860` — `createProductionEvent`

Since these use Supabase client (not Kysely), we need a new edge function `post-production-event` that the route actions call after creating/updating a production event that has an `endTime`. This follows the pattern of the other posting edge functions.

The `productionEvent.duration` column is in **seconds** (generated from `endTime - startTime`).

- [ ] **Step 1: Create the `post-production-event` edge function**

```typescript
import { serve } from "https://deno.land/std@0.175.0/http/server.ts";
import { format } from "https://deno.land/std@0.205.0/datetime/mod.ts";
import { nanoid } from "https://deno.land/x/nanoid@v3.0.0/mod.ts";
import z from "npm:zod@^3.24.1";
import { DB, getConnectionPool, getDatabaseClient } from "../lib/database.ts";
import { corsHeaders } from "../lib/headers.ts";
import { getSupabaseServiceRole } from "../lib/supabase.ts";
import { isInternalUser } from "../lib/flags.ts";
import { credit, debit, journalReference } from "../lib/utils.ts";
import { getCurrentAccountingPeriod } from "../shared/get-accounting-period.ts";
import { getNextSequence } from "../shared/get-next-sequence.ts";
import { getDefaultPostingGroup } from "../shared/get-posting-group.ts";

const pool = getConnectionPool(1);
const db = getDatabaseClient<DB>(pool);

const payloadValidator = z.object({
  productionEventId: z.string(),
  userId: z.string(),
  companyId: z.string(),
});

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const payload = await req.json();
  const today = format(new Date(), "yyyy-MM-dd");

  try {
    const { productionEventId, userId, companyId } =
      payloadValidator.parse(payload);

    const client = await getSupabaseServiceRole(
      req.headers.get("Authorization"),
      req.headers.get("carbon-key") ?? "",
      companyId
    );

    const [isInternal, companyRecord] = await Promise.all([
      isInternalUser(client, userId),
      client
        .from("company")
        .select("companyGroupId")
        .eq("id", companyId)
        .single(),
    ]);

    if (!isInternal) {
      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (companyRecord.error) throw new Error("Failed to fetch company");

    const [productionEvent, accountDefaults, dimensions] = await Promise.all([
      client
        .from("productionEvent")
        .select("*, jobOperation!inner(jobId)")
        .eq("id", productionEventId)
        .single(),
      getDefaultPostingGroup(client, companyId),
      client
        .from("dimension")
        .select("id, entityType")
        .eq("companyGroupId", companyRecord.data.companyGroupId)
        .eq("active", true)
        .in("entityType", ["ItemPostingGroup", "Location"]),
    ]);

    if (productionEvent.error) throw new Error("Failed to fetch production event");
    if (accountDefaults?.error || !accountDefaults?.data) {
      throw new Error("Error getting account defaults");
    }
    if (!accountDefaults.data.laborAbsorptionAccount) {
      throw new Error("laborAbsorptionAccount not configured in account defaults");
    }

    const event = productionEvent.data;
    if (!event.endTime || !event.duration || !event.workCenterId) {
      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const jobId = (event.jobOperation as any).jobId as string;

    const workCenter = await client
      .from("workCenter")
      .select("laborRate, quotingRate")
      .eq("id", event.workCenterId)
      .single();

    if (workCenter.error) throw new Error("Failed to fetch work center");

    const durationHours = event.duration / 3600; // duration is in seconds
    const rate =
      event.type === "Machine"
        ? Number(workCenter.data.quotingRate ?? 0)
        : Number(workCenter.data.laborRate ?? 0);

    const cost = durationHours * rate;

    if (cost <= 0) {
      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const dimensionMap = new Map<string, string>();
    if (dimensions?.data) {
      for (const dim of dimensions.data) {
        if (dim.entityType) dimensionMap.set(dim.entityType, dim.id);
      }
    }

    // Get finished good info for dimensions
    const job = await client
      .from("job")
      .select("itemId, locationId")
      .eq("id", jobId)
      .single();

    if (job.error) throw new Error("Failed to fetch job");

    const finishedItemCost = job.data.itemId
      ? await client
          .from("itemCost")
          .select("itemPostingGroupId")
          .eq("itemId", job.data.itemId)
          .eq("companyId", companyId)
          .single()
      : null;

    const journalLineReference = nanoid();

    const journalLineInserts = [
      {
        accountId: accountDefaults.data.workInProgressAccount,
        description: "WIP Account",
        amount: debit("asset", cost),
        quantity: 1,
        documentType: "Production Event",
        documentId: jobId,
        documentLineReference: journalReference.to.job(jobId),
        journalLineReference,
        companyId,
      },
      {
        accountId: accountDefaults.data.laborAbsorptionAccount!,
        description: "Labor/Machine Absorption",
        amount: credit("revenue", cost),
        quantity: 1,
        documentType: "Production Event",
        documentId: jobId,
        documentLineReference: journalReference.to.job(jobId),
        journalLineReference,
        companyId,
      },
    ];

    const accountingPeriodId = await getCurrentAccountingPeriod(
      client,
      companyId,
      db
    );

    await db.transaction().execute(async (trx) => {
      const journalEntryId = await getNextSequence(
        trx,
        "journalEntry",
        companyId
      );

      const journalResult = await trx
        .insertInto("journal")
        .values({
          journalEntryId,
          accountingPeriodId,
          description: `${event.type} Time — Job ${jobId}`,
          postingDate: today,
          companyId,
          sourceType: "Production Event",
          status: "Posted",
          postedAt: new Date().toISOString(),
          postedBy: userId,
          createdBy: userId,
        })
        .returning(["id"])
        .executeTakeFirstOrThrow();

      const journalLineResults = await trx
        .insertInto("journalLine")
        .values(
          journalLineInserts.map((line) => ({
            ...line,
            journalId: journalResult.id,
          }))
        )
        .returning(["id"])
        .execute();

      if (dimensionMap.size > 0) {
        const dimensionInserts: {
          journalLineId: string;
          dimensionId: string;
          valueId: string;
          companyId: string;
        }[] = [];

        journalLineResults.forEach((jl) => {
          if (
            finishedItemCost?.data?.itemPostingGroupId &&
            dimensionMap.has("ItemPostingGroup")
          ) {
            dimensionInserts.push({
              journalLineId: jl.id,
              dimensionId: dimensionMap.get("ItemPostingGroup")!,
              valueId: finishedItemCost.data.itemPostingGroupId,
              companyId,
            });
          }
          if (job.data.locationId && dimensionMap.has("Location")) {
            dimensionInserts.push({
              journalLineId: jl.id,
              dimensionId: dimensionMap.get("Location")!,
              valueId: job.data.locationId,
              companyId,
            });
          }
        });

        if (dimensionInserts.length > 0) {
          await trx
            .insertInto("journalLineDimension")
            .values(dimensionInserts)
            .execute();
        }
      }
    });

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error(err);
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
```

- [ ] **Step 2: Call the edge function from route actions**

In `apps/erp/app/routes/x+/job+/$jobId.events.new.tsx`, after the successful insert (around line 77), invoke the edge function if the event has an `endTime`:

```typescript
// After: const insert = await upsertProductionEvent(client, { ... });
if (!insert.error && d.endTime) {
  await client.functions.invoke("post-production-event", {
    body: {
      productionEventId: insert.data.id,
      userId,
      companyId,
    },
  });
}
```

Do the same in `apps/erp/app/routes/x+/job+/$jobId.events.$id.tsx` (after update), and in `apps/mes/app/services/operations.service.ts` (after both insert paths).

- [ ] **Step 3: Commit**

```bash
git add packages/database/supabase/functions/post-production-event/index.ts
git add apps/erp/app/routes/x+/job+/$jobId.events.new.tsx
git add apps/erp/app/routes/x+/job+/$jobId.events.$id.tsx
git add apps/mes/app/services/operations.service.ts
git commit -m "feat: add WIP journal entries for labor/machine/setup production events"
```

---

### Task 11: Job Close — Add "Closed" Status and Variance Settlement

**Files:**
- Create: `packages/database/supabase/migrations/20260504000002_job-closed-status.sql`
- Modify: `apps/erp/app/modules/production/production.models.ts` (add "Closed" to status enum)
- Modify: `apps/erp/app/routes/x+/job+/$jobId.status.tsx` (handle Closed transition)
- Modify: `packages/database/supabase/functions/issue/index.ts` (or create a new `close-job` edge function)

The `job` table currently has statuses: Draft, Planned, Ready, In Progress, Paused, Completed, Cancelled. There is no "Closed" status. Per the spec, variance settlement happens when a completed job is closed. We need to add the "Closed" status and the variance settlement logic.

- [ ] **Step 1: Add "Closed" to the job status enum**

Create migration:

```sql
-- Add "Closed" to the jobStatus enum
ALTER TYPE "jobStatus" ADD VALUE IF NOT EXISTS 'Closed';
```

- [ ] **Step 2: Update production models to include "Closed"**

In `apps/erp/app/modules/production/production.models.ts`, find the job status definitions and add "Closed" to the locked statuses alongside "Completed" and "Cancelled".

- [ ] **Step 3: Add variance settlement in the status update route**

In `apps/erp/app/routes/x+/job+/$jobId.status.tsx`, when the status transitions to "Closed", invoke an edge function that settles variance:

```typescript
if (status === "Closed") {
  await client.functions.invoke("close-job", {
    body: { jobId, userId, companyId },
  });
}
```

- [ ] **Step 4: Create `close-job` edge function (or add to `issue`)**

```typescript
import { serve } from "https://deno.land/std@0.175.0/http/server.ts";
import { format } from "https://deno.land/std@0.205.0/datetime/mod.ts";
import { nanoid } from "https://deno.land/x/nanoid@v3.0.0/mod.ts";
import z from "npm:zod@^3.24.1";
import { DB, getConnectionPool, getDatabaseClient } from "../lib/database.ts";
import { corsHeaders } from "../lib/headers.ts";
import { getSupabaseServiceRole } from "../lib/supabase.ts";
import { isInternalUser } from "../lib/flags.ts";
import { credit, debit, journalReference } from "../lib/utils.ts";
import { getCurrentAccountingPeriod } from "../shared/get-accounting-period.ts";
import { getNextSequence } from "../shared/get-next-sequence.ts";
import { getDefaultPostingGroup } from "../shared/get-posting-group.ts";

const pool = getConnectionPool(1);
const db = getDatabaseClient<DB>(pool);

const payloadValidator = z.object({
  jobId: z.string(),
  userId: z.string(),
  companyId: z.string(),
});

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const payload = await req.json();
  const today = format(new Date(), "yyyy-MM-dd");

  try {
    const { jobId, userId, companyId } = payloadValidator.parse(payload);

    const client = await getSupabaseServiceRole(
      req.headers.get("Authorization"),
      req.headers.get("carbon-key") ?? "",
      companyId
    );

    const [isInternal, companyRecord] = await Promise.all([
      isInternalUser(client, userId),
      client
        .from("company")
        .select("companyGroupId")
        .eq("id", companyId)
        .single(),
    ]);

    if (!isInternal) {
      return new Response(JSON.stringify({ success: true }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (companyRecord.error) throw new Error("Failed to fetch company");

    const accountDefaults = await getDefaultPostingGroup(client, companyId);
    if (accountDefaults?.error || !accountDefaults?.data) {
      throw new Error("Error getting account defaults");
    }

    // Calculate remaining WIP balance for this job
    // Sum all journal line amounts where the account is WIP and the document is this job
    await db.transaction().execute(async (trx) => {
      const wipBalance = await trx
        .selectFrom("journalLine")
        .innerJoin("journal", "journal.id", "journalLine.journalId")
        .select((eb) => eb.fn.sum("journalLine.amount").as("balance"))
        .where(
          "journalLine.accountId",
          "=",
          accountDefaults.data!.workInProgressAccount
        )
        .where("journalLine.documentId", "=", jobId)
        .where("journal.companyId", "=", companyId)
        .executeTakeFirst();

      const remainingWip = Number(wipBalance?.balance ?? 0);

      // If WIP still has a net balance, post variance to clear it
      // A positive balance means debits > credits (cost not fully discharged)
      if (Math.abs(remainingWip) < 0.01) return;

      const journalLineReference = nanoid();

      const journalLineInserts = [
        {
          accountId: accountDefaults.data!.materialVarianceAccount,
          description: "Production Variance",
          amount: debit("expense", Math.abs(remainingWip)),
          quantity: 0,
          documentType: "Job Close",
          documentId: jobId,
          documentLineReference: journalReference.to.job(jobId),
          journalLineReference,
          companyId,
        },
        {
          accountId: accountDefaults.data!.workInProgressAccount,
          description: "WIP Account",
          amount: credit("asset", Math.abs(remainingWip)),
          quantity: 0,
          documentType: "Job Close",
          documentId: jobId,
          documentLineReference: journalReference.to.job(jobId),
          journalLineReference,
          companyId,
        },
      ];

      const accountingPeriodId = await getCurrentAccountingPeriod(
        client,
        companyId,
        db
      );

      const journalEntryId = await getNextSequence(
        trx,
        "journalEntry",
        companyId
      );

      const journalResult = await trx
        .insertInto("journal")
        .values({
          journalEntryId,
          accountingPeriodId,
          description: `Job Close Variance ${jobId}`,
          postingDate: today,
          companyId,
          sourceType: "Job Close",
          status: "Posted",
          postedAt: new Date().toISOString(),
          postedBy: userId,
          createdBy: userId,
        })
        .returning(["id"])
        .executeTakeFirstOrThrow();

      await trx
        .insertInto("journalLine")
        .values(
          journalLineInserts.map((line) => ({
            ...line,
            journalId: journalResult.id,
          }))
        )
        .execute();
    });

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error(err);
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
```

- [ ] **Step 5: Commit**

```bash
git add packages/database/supabase/migrations/20260504000002_job-closed-status.sql
git add packages/database/supabase/functions/close-job/index.ts
git add apps/erp/app/modules/production/production.models.ts
git add apps/erp/app/routes/x+/job+/$jobId.status.tsx
git commit -m "feat: add Closed job status and production variance settlement"
```

---

### Task 12: Verify End-to-End — Ship and Invoice a Bought Product

- [ ] **Step 1: Apply migrations**

Run the database migrations to add `remainingQuantity` and `laborAbsorptionAccount`.

- [ ] **Step 2: Test post-shipment journal entries**

Create a sales order with an inventory item, ship it, and verify:
- Journal entry is created with DR COGS / CR Inventory
- Amounts use actual inventory cost (not selling price)
- Dimensions (CustomerType, ItemPostingGroup, Location) are attached
- costLedger entry is created with `itemLedgerType: "Sale"`

- [ ] **Step 3: Test post-sales-invoice (SO-linked)**

Invoice the same sales order and verify:
- Journal entry has ONLY DR AR / CR Revenue
- NO COGS/Inventory entries (those were at shipment)
- Dimensions are attached

- [ ] **Step 4: Test post-sales-invoice (direct, no SO)**

Create a direct sales invoice (no sales order) and verify:
- Journal entry has DR AR / CR Revenue AND DR COGS / CR Inventory
- COGS uses actual inventory cost from the COGS engine
- costLedger entry is created

- [ ] **Step 5: Verify update-purchased-prices**

Finalize a PO and verify costLedger entries have `remainingQuantity` set.

---

### Task 13: Verify End-to-End — Manufacture and Ship a Product

- [ ] **Step 1: Test material issuance WIP**

Run a job operation that issues materials and verify:
- Journal entry: DR WIP / CR Raw Material Inventory
- costLedger entry for consumption
- Dimensions (ItemPostingGroup, Location, CostCenter) attached

- [ ] **Step 2: Test job completion**

Complete the job and verify:
- Journal entry: DR FG Inventory / CR WIP
- costLedger entry for the finished good (with `remainingQuantity`)
- `itemCost.unitCost` updated for Average cost items

- [ ] **Step 3: Test shipping the manufactured product**

Ship the finished good and verify:
- Journal entry: DR COGS / CR Inventory
- COGS uses the cost from the job completion costLedger entry
- For FIFO: the cost layer from the job is consumed

- [ ] **Step 4: Test job close variance**

Close the job and verify:
- If WIP balance remains, variance journal entry is created
- WIP account balance is zero after close
