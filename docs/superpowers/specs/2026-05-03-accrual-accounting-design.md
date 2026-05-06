# Accrual Accounting Rewrite: COGS, Shipment Journal Entries, Dimensions & WIP

## Problem Statement

Three critical issues with the current accrual accounting implementation:

1. **No journal entries on shipment**: `post-shipment` creates item ledger entries but zero GL impact. COGS is never recognized when goods leave the warehouse.
2. **No dimensions on sales transactions**: `post-sales-invoice` never attaches dimensions (ItemPostingGroup, Location, CustomerType) to journal lines. Purchase-side functions do.
3. **Inaccurate COGS**: `post-sales-invoice` uses the invoice line's selling price (`unitPrice`) as COGS instead of the actual inventory cost. COGS = Revenue, which is incorrect.

Additionally:
- **No costLedger entries for manufactured parts**: Job completion creates item ledger entries but never writes to costLedger, so there's no cost basis for COGS on manufactured goods.
- **No WIP accounting**: Material issuance, labor, and machine time during production have no GL impact.

## Approach: NetSuite-Style (Approach A)

Based on research of both NetSuite and SAP best practices, both systems agree:

- **COGS at shipment, Revenue at invoice** — COGS follows the physical goods movement, revenue follows the billing event
- **Manufacturing uses WIP -> FG Inventory -> Variance** — incremental WIP accounting during production, discharge at completion
- **Dimensions inherited from source documents** — never manually assigned on automated postings

## Design

### Section 1: Shipment Posting — Journal Entries

**File**: `packages/database/supabase/functions/post-shipment/index.ts`

When a shipment is posted for a sales order, create journal entries:

| Account | Debit | Credit | Source |
|---------|-------|--------|--------|
| Cost of Goods Sold | $X | | COGS calculation engine |
| Inventory | | $X | Same amount |

Cost source: The COGS calculation engine (Section 2) determines `$X` based on the item's `costingMethod` from `itemCost`.

Dimensions attached: ItemPostingGroup (from itemCost), Location (from shipment line), CustomerType (from sales order customer).

Edge cases:
- Non-inventory items: No COGS entry (no inventory to relieve)
- Outside processing items: Use WIP account instead of Inventory for credit
- Intercompany: Use IC COGS account if applicable

### Section 2: COGS Calculation Engine

New shared module usable by `post-shipment` and `post-sales-invoice` (for direct invoices).

```
calculateCOGS(itemId, quantity, companyId, costingMethod) -> { unitCost, totalCost, layersConsumed[] }
```

**By costing method:**

**Standard Cost**:
- Query `itemCost.standardCost`
- `totalCost = standardCost * quantity`
- No costLedger interaction

**Average Cost**:
- Query `itemCost.unitCost` (maintained as weighted average by `update-purchased-prices`)
- `totalCost = unitCost * quantity`
- No costLedger interaction

**FIFO**:
- Query costLedger entries ordered by `postingDate ASC, createdAt ASC`
- Only entries with `remainingQuantity > 0`
- Consume layers oldest-first until quantity fulfilled
- Return `{ costLedgerId, quantityConsumed, unitCost }[]` for audit

**LIFO**:
- Same as FIFO but ordered `postingDate DESC, createdAt DESC`

The engine also writes a costLedger entry for the shipment:
- `itemLedgerType: "Sale"`, `costLedgerType: "Direct Cost"`
- `documentType: "Sales Shipment"`, `quantity: -quantity`, `cost: -totalCost`

For FIFO/LIFO, update `remainingQuantity` on each consumed layer within the same transaction.

Fallback: If insufficient layers exist (negative inventory scenario), fall back to `itemCost.unitCost`.

### Section 3: Sales Invoice Posting Changes

**File**: `packages/database/supabase/functions/post-sales-invoice/index.ts`

**When a shipment already exists** (ship first, invoice later):
- Invoice posts revenue only: DR Accounts Receivable / CR Sales Revenue
- No COGS entries (already posted at shipment)
- No item ledger entries (already relieved at shipment)

**When invoice is posted before shipment** (invoice first, ship later):
- Invoice posts revenue only: DR Accounts Receivable / CR Sales Revenue
- COGS posted later when shipment occurs (Section 1 handles this)

**Direct invoice (no sales order)**:
- Invoice posts both sides using the COGS calculation engine:
  - DR Accounts Receivable / CR Sales Revenue (selling price)
  - DR COGS / CR Inventory (actual cost from engine — NOT the selling price)
- Creates item ledger and shipment lines as today

**Key fix**: Revenue and COGS are now from different sources. Revenue = selling price. COGS = actual inventory cost.

Dimensions attached: ItemPostingGroup, Location, CustomerType (matching shipment pattern).

### Section 4: WIP Accounting & Job Completion

Four events build up WIP during production, one discharges it.

**4a. Material Issuance to Job**

| Account | Debit | Credit |
|---------|-------|--------|
| WIP | material cost | |
| Raw Material Inventory | | material cost |

Cost determined by the issued material's costing method via the COGS calculation engine. Writes a costLedger entry for consumption (`itemLedgerType: "Consumption"`).

**4b. Labor/Machine/Setup Time Recording**

When a production event completes (has `endTime`):

| Account | Debit | Credit |
|---------|-------|--------|
| WIP | time * rate | |
| Labor/Machine Absorption | | time * rate |

Rate from work center or operation cost rate.

**4c. Outside Processing Receipt**

Already handled by `post-receipt` — posts DR WIP / CR GR/IR for outside processing items. No changes needed.

**4d. Job Completion (Discharge WIP -> Finished Goods)**

| Account | Debit | Credit |
|---------|-------|--------|
| Finished Goods Inventory | actual accumulated cost | |
| WIP | | actual accumulated cost |

Actual accumulated cost = sum of all WIP debits (4a + 4b + 4c) for this job.

Writes costLedger entry for the finished good:
- `itemLedgerType: "Output"`, `documentType: "Job Receipt"`
- `quantity: quantityComplete`, `cost: actual accumulated cost`
- `remainingQuantity: quantityComplete` (FIFO/LIFO layer)

Updates `itemCost.unitCost` for Average cost items.

**4e. Job Close (Variance Settlement)**

When a completed job is closed, if WIP balance remains:

| Account | Debit | Credit |
|---------|-------|--------|
| Production Variance | remaining WIP | |
| WIP | | remaining WIP |

Variance accounts from `accountDefault`: `materialVarianceAccount`, `laborAndMachineVarianceAccount`, `overheadVarianceAccount`, `lotSizeVarianceAccount`.

**Dimensions on all WIP entries**: ItemPostingGroup (from finished good), Location (from job), Department (from job if assigned).

### Section 5: Dimensions on All Transactions

Standardize dimension attachment across all posting functions.

| Transaction | ItemPostingGroup | Location | CustomerType | SupplierType | CostCenter |
|-------------|-----------------|----------|--------------|--------------|------------|
| Purchase Receipt | From itemCost | From receipt line | — | From supplier | — |
| Purchase Invoice | From itemCost | From invoice line | — | From supplier | From GL account line |
| Sales Shipment (new) | From itemCost | From shipment line | From customer | — | From SO line |
| Sales Invoice (fix) | From itemCost | From invoice line | From customer | — | From SO line |
| Job Material Issue (new) | From material's itemCost | From job location | — | — | From job |
| Job Labor/Machine (new) | From finished good's itemCost | From job location | — | — | From job |
| Job Completion (new) | From finished good's itemCost | From job location | — | — | From job |

Inheritance rule: Line-level > Header-level > Entity-level default.

No changes to `post-receipt` or `post-purchase-invoice` (already correct).

### Section 6: costLedger as Cost Layer System

Add one column to `costLedger`:

```sql
ALTER TABLE "costLedger" ADD COLUMN "remainingQuantity" NUMERIC(12, 4) NOT NULL DEFAULT 0;
```

**Layer creation** (remainingQuantity set to quantity):

| Event | itemLedgerType | documentType |
|-------|---------------|--------------|
| Purchase receipt | Purchase | Purchase Receipt |
| Job completion | Output | Job Receipt |
| Positive inventory adjustment | Positive Adjmt. | — |
| Transfer receipt | Transfer | Transfer Receipt |

**Layer consumption** (remainingQuantity decremented, FIFO/LIFO only):

| Event | itemLedgerType | documentType |
|-------|---------------|--------------|
| Sales shipment | Sale | Sales Shipment |
| Material issue to job | Consumption | — |
| Negative inventory adjustment | Negative Adjmt. | — |

Standard/Average items: Layers created for audit trail but `remainingQuantity` not consumed on shipment.

**update-purchased-prices changes**: Initialize `remainingQuantity = quantity` when creating layers from PO finalization. Keep existing average cost calculation.

### Backfill Strategy

For existing data, add `remainingQuantity` to historical costLedger entries.

**For each item + company:**

1. Calculate current on-hand: `SUM(itemLedger.quantity)`
2. For FIFO items: Walk costLedger newest-to-oldest, assign `remainingQuantity` until on-hand accounted for (newest layers are what remain after oldest were consumed)
3. For LIFO items: Walk oldest-to-newest
4. For Standard/Average: Set `remainingQuantity = quantity` on all inbound entries

**Gap handling** (on-hand > costLedger total): Create synthetic opening balance entry:
- "Buy" items (`item.replenishmentSystem = 'Buy'`): `itemLedgerType: "Purchase"`, `documentType: "Purchase Receipt"`
- "Make"/"Buy and Make" items: `itemLedgerType: "Output"`, `documentType: "Job Receipt"`
- Cost = `gap * itemCost.unitCost`
- Date = earliest itemLedger entry date for that item (ensures synthetic layers are consumed first in FIFO)

## Deployment Strategy

**Big bang cutover with reconciliation** — not a gradual rollout.

**Phase 1: Deploy costLedger changes (always on, no GL impact)**
- Add `remainingQuantity` column
- Run backfill migration
- Start writing `remainingQuantity` on all new costLedger entries (receipts, PO finalization)
- Start consuming layers on shipments (update `remainingQuantity` in costLedger) — this is data-only, no journal entries
- Write costLedger entries on job completion (data-only, no journal entries)
- **Keep existing journal entry behavior unchanged** — sales invoice still posts COGS the old way during this phase
- The costLedger becomes the source of truth for what a reconciliation entry needs to contain at cutover

**Phase 2: Cutover day**
- Flip the `isInternalUser` flag (or equivalent feature flag)
- Run one-time reconciliation: create opening balance journal entries based on costLedger state at cutover
- All new transactions use the new journal entry behavior going forward

**Why not gradual**: If we change WHEN COGS is posted (shipment vs invoice) but don't create journal entries at the new timing, neither shipment nor invoice posts COGS — worse than the current broken behavior. WIP accounting also can't be partially enabled because incremental WIP debits must exist before completion can credit WIP.

## Accounts Used

All accounts already exist in `accountDefault`:

| Account | Used By |
|---------|---------|
| `costOfGoodsSoldAccount` | Shipment COGS debit |
| `inventoryAccount` | Shipment/invoice inventory credit |
| `receivablesAccount` | Invoice AR debit |
| `salesAccount` | Invoice revenue credit |
| `workInProgressAccount` | WIP debit (materials, labor, machine) |
| `payablesAccount` | Purchase invoice AP credit |
| `goodsReceivedNotInvoicedAccount` | GR/IR clearing (unchanged) |
| `purchaseVarianceAccount` | PPV (unchanged) |
| `materialVarianceAccount` | Production variance |
| `laborAndMachineVarianceAccount` | Production variance |
| `overheadVarianceAccount` | Production variance |
| `lotSizeVarianceAccount` | Production variance |

New account needed in `accountDefault`: **laborAbsorptionAccount** — the credit side of WIP labor/machine entries. This is the cost center "sending" its capacity to the job. Requires a new column on `accountDefault` and a migration to add it.

## Files Modified

| File | Change |
|------|--------|
| `packages/database/supabase/functions/post-shipment/index.ts` | Add journal entries (COGS + dimensions) |
| `packages/database/supabase/functions/post-sales-invoice/index.ts` | Remove COGS from invoice, add dimensions, fix cost source |
| `packages/database/supabase/functions/update-purchased-prices/index.ts` | Set remainingQuantity on costLedger inserts |
| `packages/database/supabase/functions/issue/index.ts` | Add costLedger + journal entries on job completion |
| `packages/database/supabase/migrations/` | Add remainingQuantity column + backfill |
| New: shared COGS calculation engine | Shared by post-shipment and post-sales-invoice |
| New: WIP journal entry logic | Triggered by material issuance, production events |
| New: Job close variance settlement | New edge function or extension of existing |
