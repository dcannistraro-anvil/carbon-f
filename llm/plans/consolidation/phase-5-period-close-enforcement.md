# Phase 5: Period-Close Enforcement

## Goal

Prevent posting journal entries to closed accounting periods. This is the foundation for all subsequent phases since every posting path writes to the `journal` table.

## Current State

- `accountingPeriod` table has `status` enum (`Active`, `Inactive`) and `closedAt`/`closedBy` fields
- `getCurrentAccountingPeriod()` in `packages/database/supabase/functions/shared/get-accounting-period.ts` finds the active period but does not reject writes to closed periods
- All posting functions (post-purchase-invoice, post-sales-invoice, post-receipt, elimination JEs, manual JEs) insert into the `journal` table with an `accountingPeriodId` FK
- Periods are per-company (`accountingPeriod.companyId`)

## Design

### Single Enforcement Point

A Postgres trigger on `journal` INSERT is the cleanest approach. Every posting path — edge functions, manual JEs, elimination entries — goes through `journal`. One trigger catches them all without modifying each posting function individually.

### Schema Changes

1. Add `'Closed'` to the `accountingPeriodStatus` enum
2. Create trigger function `assert_accounting_period_open()`:
   - On `journal` INSERT, look up the referenced `accountingPeriodId`
   - If status = `'Closed'`, raise exception: `'Cannot post to closed accounting period'`
   - If no period referenced (NULL), allow (some system entries may not have a period)

### Period Close/Reopen Logic

- Close: Set `status = 'Closed'`, `closedAt = now()`, `closedBy = userId`
- Reopen: Set `status = 'Active'`, clear `closedAt`/`closedBy` (requires elevated permission)
- Permission: `accounting_close` on the company's root company group

### Service Layer

Add to `accounting.service.ts`:
- `closeAccountingPeriod(companyId, periodId, userId)` — validates all prior periods are closed, sets status
- `reopenAccountingPeriod(companyId, periodId, userId)` — only if no subsequent period is closed

### UI

- Add close/reopen button on the accounting period detail page
- Show closed status badge on period list
- Disable posting forms when the target period is closed (UX guard, not the enforcement point)

### Constraints

- Periods must be closed in order (can't close March if February is still open)
- Reopening a period also reopens all subsequent periods (cascade)
- Elimination entries respect the same enforcement — must run eliminations before closing

## Migration

```sql
-- Add 'Closed' to accountingPeriodStatus enum
ALTER TYPE "accountingPeriodStatus" ADD VALUE 'Closed';

-- Trigger function
CREATE OR REPLACE FUNCTION assert_accounting_period_open()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW."accountingPeriodId" IS NOT NULL THEN
    PERFORM 1 FROM "accountingPeriod"
    WHERE "id" = NEW."accountingPeriodId"
    AND "status" = 'Closed';

    IF FOUND THEN
      RAISE EXCEPTION 'Cannot post to closed accounting period (periodId: %)', NEW."accountingPeriodId";
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger on journal INSERT
CREATE TRIGGER trg_journal_assert_period_open
  BEFORE INSERT ON "journal"
  FOR EACH ROW
  EXECUTE FUNCTION assert_accounting_period_open();
```

## Files to Modify

| File | Change |
|------|--------|
| New migration | Enum + trigger |
| `accounting.service.ts` | `closeAccountingPeriod()`, `reopenAccountingPeriod()` |
| `accounting.models.ts` | Validators for close/reopen |
| Period detail route | Close/reopen UI |
| Period list route | Status badge |
