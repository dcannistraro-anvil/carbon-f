# MTO Shipment COGS Recognition

> **For agentic workers:** Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make MTO (Make-to-Order) shipment posting recognize COGS from the job by routing MTO jobs through `complete_job_to_inventory()` and removing the `continue` statements that skip GL/inventory posting in `post-shipment`.

**Architecture:** Unify MTO and MTS job completion paths so both call `complete_job_to_inventory()`. This creates cost layers in `costLedger` and itemLedger entries for the finished good. Then remove the `continue` statements in `post-shipment/index.ts` so MTO shipment lines go through the same COGS/inventory posting as regular lines.

**Tech Stack:** PostgreSQL (PL/pgSQL migrations), TypeScript (Deno edge functions)

---

### Task 1: New migration — unify `sync_finish_job_operation` for MTO and MTS

**Files:**
- Create: `packages/database/supabase/migrations/20260512120000_mto-shipment-cogs.sql`

The current `sync_finish_job_operation` trigger (defined in `20260511120000_backflush-job-materials.sql:860-935`) branches on `v_sales_order_id IS NOT NULL`. MTO jobs only call `backflush_job_materials()`, while MTS jobs call `complete_job_to_inventory()` (which internally calls `backflush_job_materials()`). We need MTO to also call `complete_job_to_inventory()`.

- [ ] **Step 1: Write the migration**

```sql
-- Unify MTO and MTS job completion: both now call complete_job_to_inventory
-- Previously, MTO jobs only called backflush_job_materials(), skipping
-- cost layer creation. This meant shipment posting had no cost layers
-- to consume for COGS.

CREATE OR REPLACE FUNCTION sync_finish_job_operation(
  p_new JSONB,
  p_old JSONB,
  p_operation TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job_location_id TEXT;
  v_job_storage_unit_id TEXT;
  v_job_quantity NUMERIC;
  v_sales_order_id TEXT;
  v_quantity_complete NUMERIC;
  v_job_status TEXT;
BEGIN
  IF p_operation != 'UPDATE' THEN RETURN; END IF;
  IF (p_new->>'status') != 'Done' OR (p_old->>'status') = 'Done' THEN RETURN; END IF;

  -- Close all open production events for this operation
  UPDATE "productionEvent"
  SET "endTime" = NOW()
  WHERE "jobOperationId" = p_new->>'id'
    AND "endTime" IS NULL;

  -- Unlock dependent operations whose dependencies are now all done
  UPDATE "jobOperation" op
  SET status = 'Ready'
  WHERE EXISTS (
    SELECT 1
    FROM "jobOperationDependency" dep
    WHERE dep."operationId" = op.id
      AND dep."dependsOnId" = p_new->>'id'
      AND op.status = 'Waiting'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM "jobOperationDependency" dep2
    JOIN "jobOperation" jo2 ON jo2.id = dep2."dependsOnId"
    WHERE dep2."operationId" = op.id
      AND jo2.status != 'Done'
      AND jo2.id != p_new->>'id'
  );

  -- Only complete the job if it is in an active state (has been released/started)
  SELECT status INTO v_job_status FROM "job" WHERE id = p_new->>'jobId';
  IF v_job_status NOT IN ('Ready', 'In Progress', 'Paused') THEN
    RETURN;
  END IF;

  -- If this is the last operation, mark the job as Completed
  IF is_last_job_operation(p_new->>'id') THEN
    SELECT "locationId", "storageUnitId", quantity, "salesOrderId"
    INTO v_job_location_id, v_job_storage_unit_id, v_job_quantity, v_sales_order_id
    FROM "job"
    WHERE id = p_new->>'jobId';

    v_quantity_complete := CASE
      WHEN COALESCE((p_new->>'quantityComplete')::NUMERIC, 0) = 0 THEN v_job_quantity
      ELSE (p_new->>'quantityComplete')::NUMERIC
    END;

    PERFORM complete_job_to_inventory(
      p_job_id := p_new->>'jobId',
      p_quantity_complete := v_quantity_complete,
      p_storage_unit_id := v_job_storage_unit_id,
      p_location_id := v_job_location_id,
      p_company_id := p_new->>'companyId',
      p_user_id := p_new->>'updatedBy'
    );
  END IF;
END;
$$;
```

- [ ] **Step 2: Verify migration syntax**

Run: `cd /Users/barbinbrad/Code/carbon && grep -c "CREATE OR REPLACE FUNCTION sync_finish_job_operation" packages/database/supabase/migrations/20260512120000_mto-shipment-cogs.sql`
Expected: `1`

- [ ] **Step 3: Commit**

```bash
git add packages/database/supabase/migrations/20260512120000_mto-shipment-cogs.sql
git commit -m "feat: unify MTO/MTS job completion to both call complete_job_to_inventory

Previously MTO jobs only called backflush_job_materials(), skipping cost
layer creation in costLedger. This meant shipment posting had no cost
layers to consume for COGS recognition.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 2: Remove `continue` in post-shipment posting flow

**Files:**
- Modify: `packages/database/supabase/functions/post-shipment/index.ts:322`

The `continue` on line 322 causes MTO shipment lines (fulfillment type "Job") to skip all downstream processing: itemLedger creation, COGS journal entries, cost layer consumption. After Task 1, MTO finished goods will have proper cost layers, so we can let them flow through the normal COGS path.

- [ ] **Step 1: Remove the `continue` statement**

In `packages/database/supabase/functions/post-shipment/index.ts`, delete line 322 (`continue;`). The job update block (lines 215-321) should still run, but then fall through to the itemLedger/COGS code below instead of skipping it.

The change is deleting this single line:
```typescript
                // BEFORE (line 322):
                continue;
```

After the closing brace of the job update block on line 321 (`}`), the code should fall through to line 325 (`const itemTrackingType = ...`).

- [ ] **Step 2: Verify the change**

Run: `grep -n "continue;" packages/database/supabase/functions/post-shipment/index.ts | head -5`

The `continue` that was on line 322 should no longer appear in the posting section (lines 210-460). There may still be a `continue` in the void section — that's Task 3.

- [ ] **Step 3: Commit**

```bash
git add packages/database/supabase/functions/post-shipment/index.ts
git commit -m "feat: enable COGS posting for MTO shipment lines

Remove continue statement that skipped itemLedger, COGS journal entries,
and cost layer consumption for job-fulfilled shipment lines.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### Task 3: Remove `continue` in post-shipment void flow

**Files:**
- Modify: `packages/database/supabase/functions/post-shipment/index.ts:1753`

The void flow has the same issue: MTO shipment lines skip inventory restoration and COGS reversal journal entries.

- [ ] **Step 1: Remove the `continue` statement in the void section**

In `packages/database/supabase/functions/post-shipment/index.ts`, delete the `continue;` on line 1753 (this line number may have shifted by -1 after Task 2). It's inside the void flow's job update block, after `jobUpdates[jobId] = { ... }` on line 1747-1751.

The change is deleting this single line:
```typescript
                // BEFORE (line 1753, or 1752 after Task 2):
                continue;
```

After removing it, the void flow will fall through to create positive adjustment itemLedger entries (restoring inventory), batch/serial tracking restoration, and COGS reversal journal entries for MTO lines.

- [ ] **Step 2: Verify the change**

Run: `grep -n "continue;" packages/database/supabase/functions/post-shipment/index.ts`

There should be no `continue` statements remaining inside either the post or void shipment line loops related to job fulfillment.

- [ ] **Step 3: Commit**

```bash
git add packages/database/supabase/functions/post-shipment/index.ts
git commit -m "feat: enable COGS reversal for voided MTO shipments

Remove continue statement that skipped inventory restoration and COGS
reversal journal entries for job-fulfilled shipment lines during void.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Review

After all three tasks, verify:

- [ ] `sync_finish_job_operation` no longer branches on `salesOrderId` — both MTO and MTS call `complete_job_to_inventory()`
- [ ] `complete_job_to_inventory()` calls `backflush_job_materials()` internally (line 513 of 20260511 migration), so no double-backflush
- [ ] Post-shipment posting flow: MTO lines create itemLedger entries, COGS journal entries, and consume cost layers
- [ ] Post-shipment void flow: MTO lines create reversal itemLedger entries and COGS reversal journal entries
- [ ] Job quantity tracking (quantityShipped, quantityComplete, status) still works — that code runs before the removed `continue`

## Notes

- Migration file: `packages/database/supabase/migrations/20260512120000_mto-shipment-cogs.sql`
- Edge function: `packages/database/supabase/functions/post-shipment/index.ts`
- `complete_job_to_inventory` is defined in `20260511120000_backflush-job-materials.sql:342-837`
- `backflush_job_materials` is defined in `20260511120000_backflush-job-materials.sql:1-340`
- `calculateCOGS` is at `packages/database/supabase/functions/shared/calculate-cogs.ts`
