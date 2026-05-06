# Phase 9: Period-Close Workflow UI

## Goal

Provide a structured period-close checklist that guides accountants through the required steps in order, culminating in locking the period. This is the last-mile UX that ties together Phases 2, 3, 5, and 7.

## Dependencies

- Phase 5 (period-close enforcement) — the close/lock mechanism
- Phase 2 (currency translation) — FX revaluation step
- Phase 3 (IC elimination) — elimination step
- Phase 7 (CTA-E) — elimination handles FX differences
- Phase 4 (consolidated statements) — review step

## Design

### Period-Close Checklist

Route: `/x/accounting/period-close/:companyId/:periodId`

Steps executed in order, per company:

| Step | Action | Prerequisite |
|------|--------|-------------|
| 1. Review open items | Show unposted invoices, receipts, pending JEs | None |
| 2. Revalue foreign currency | Run `translateTrialBalance()` for this company, review CTA | Step 1 reviewed |
| 3. Match IC transactions | Run `matchIntercompanyTransactions()`, review unmatched | Step 2 complete |
| 4. Generate elimination entries | Run `generateEliminationEntries()` (with CTA-E from Phase 7) | Step 3 complete, all matched |
| 5. Review trial balance | Show per-company trial balance for final review | Step 4 complete |
| 6. Close period | Call `closeAccountingPeriod()` — locks the period | Step 5 reviewed |

### Step Status Model

Each step has a status derived from the system state (not a separate table):

- **Step 1**: `pending` if unposted documents exist, `ready` otherwise
- **Step 2**: `pending` if not run this period, `complete` if FX revaluation ran
- **Step 3**: `pending` if unmatched IC transactions exist, `complete` if all matched (or none exist)
- **Step 4**: `pending` if matched-but-not-eliminated transactions exist, `complete` if all eliminated
- **Step 5**: Always `ready` (informational review)
- **Step 6**: `ready` when steps 1-5 are complete, `complete` when period is closed

### Service Layer

Add to `accounting.service.ts`:

```typescript
getPeriodCloseStatus(companyId: string, periodId: string): Promise<PeriodCloseStatus>
```

Returns the status of each step by querying:
- Unposted documents for the period
- Last FX revaluation run date vs period end
- Unmatched/matched/eliminated IC transaction counts
- Period status

### UI Components

- `PeriodCloseChecklist` — vertical stepper showing all 6 steps with status badges
- Each step expands to show details and action button
- Steps are disabled until prerequisites are met
- "Close Period" button requires confirmation dialog

### Group-Level View

Route: `/x/accounting/period-close`

Shows all companies in the group with their close status for the current period:
- Company name | Period | Steps completed (e.g., "4/6") | Status badge
- Click through to per-company checklist

## Files to Create/Modify

| File | Change |
|------|--------|
| New route: `period-close.tsx` | Group-level overview |
| New route: `period-close.$companyId.$periodId.tsx` | Per-company checklist |
| `accounting.service.ts` | `getPeriodCloseStatus()` |
| New UI component: `PeriodCloseChecklist` | Stepper component |
| `accounting.models.ts` | Types for close status |
