# MTO Material Backflush

## Plan

- [x] Write design spec
- [x] Step 1: Create `backflush_job_materials` function in a new migration
- [x] Step 2: Refactor `complete_job_to_inventory` to call `backflush_job_materials`
- [x] Step 3: Update `sync_finish_job_operation` to call `backflush_job_materials` for MTO
- [x] Step 4: Update ERP route `$jobId.complete.tsx` to call `backflush_job_materials` for MTO
- [x] Step 5: Verify — read all changed files and confirm correctness

## Notes

- Spec: `docs/superpowers/specs/2026-05-11-mto-backflush-design.md`
- Migration file: `packages/database/supabase/migrations/20260508120000_complete-job-to-inventory.sql`
- ERP route: `apps/erp/app/routes/x+/job+/$jobId.complete.tsx`
- The backflush logic to extract is lines 193-593 of the migration
- Prorate formula: `target = estimatedQuantity * (p_quantity_complete / job.quantity)`, `to_backflush = GREATEST(target - quantityIssued, 0)`
