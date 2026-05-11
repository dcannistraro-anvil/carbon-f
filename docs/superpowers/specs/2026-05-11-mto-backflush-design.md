# MTO Material Backflush Design

## Problem

When a make-to-order (MTO) job completes, unissued materials are not backflushed from inventory. Make-to-stock (MTS) jobs handle this via `complete_job_to_inventory`, but MTO jobs skip that function entirely — the trigger just updates job status, and the ERP route only calls it for leftover inventory receipt.

Materials may be partially issued during production via the MES `issue` edge function (proportionally per operation completion), but if any remain unissued at job completion, nothing catches them.

## Solution

Extract the backflush logic from `complete_job_to_inventory` into a reusable `backflush_job_materials` function. Call it from both MTO and MTS completion paths.

## New Function

```sql
backflush_job_materials(
  p_job_id TEXT,
  p_quantity_complete NUMERIC,
  p_company_id TEXT,
  p_user_id TEXT
)
```

### Logic

1. Look up `job.quantity` (original job quantity) and `job.locationId`
2. Loop through unissued non-tracked materials:
   - Filter: `jobMaterial` where `jobId = p_job_id`, `itemType IN ('Material', 'Part', 'Consumable')`, `methodType != 'Make to Order'`, `requiresBatchTracking = false`, `requiresSerialTracking = false`, `quantityToIssue > 0`
3. For each material, prorate based on actual completion:
   - `target = estimatedQuantity * (p_quantity_complete / job.quantity)`
   - `to_backflush = GREATEST(target - quantityIssued, 0)`
   - Skip if `to_backflush <= 0`
4. Resolve storage unit: explicit on jobMaterial -> pickMethod default -> largest inventory bucket at job location
5. Create negative `itemLedger` consumption entry
6. Update `jobMaterial.quantityIssued`
7. If accounting enabled:
   - Calculate COGS per costing method (Standard/Average/FIFO/LIFO with cost layer consumption)
   - Post journal entry: DR WIP / CR Inventory
   - Create costLedger consumption entry
   - Attach dimensions (ItemPostingGroup, Location)

### Idempotency

Safe to call even if all materials are fully issued — `quantityToIssue` will be 0 and the loop won't execute. Also safe if `p_quantity_complete` produces a target less than or equal to what's already issued.

## Refactor `complete_job_to_inventory`

Replace the inline backflush block (lines 193-593) with:

```sql
PERFORM backflush_job_materials(p_job_id, p_quantity_complete, p_company_id, p_user_id);
```

No behavior change for MTS jobs. Labor/machine absorption, WIP discharge, output itemLedger, and cost updates remain in `complete_job_to_inventory`.

## MTO Completion Paths

### Trigger (`sync_finish_job_operation`)

In the MTO branch (where `v_sales_order_id IS NOT NULL`), add after the job status update:

```sql
PERFORM backflush_job_materials(p_new->>'jobId', v_quantity_complete, p_new->>'companyId', p_new->>'updatedBy');
```

### ERP Route (`$jobId.complete.tsx`)

In the MTO branch, add after the job status update:

```typescript
await client.rpc("backflush_job_materials", {
  p_job_id: jobId,
  p_quantity_complete: quantityComplete,
  p_company_id: companyId,
  p_user_id: userId,
});
```

## Out of Scope

- Labor/machine absorption posting for MTO (stays in `complete_job_to_inventory`)
- WIP discharge at shipment (separate flow)
- Tracked material (batch/serial) backflushing
