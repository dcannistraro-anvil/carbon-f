# Financial Consolidation PRD

## Why

Carbon has built strong multi-entity infrastructure — company groups, shared chart of accounts, accounting dimensions, elimination entities — but none of it connects yet. The elimination entity is an empty shell. `accountTreeBalances` aggregates across all companies with no per-company filter. There are no financial statement pages. No intercompany matching. No currency translation. No consolidation.

This PRD defines a 4-phase plan to activate all of that infrastructure into a working financial consolidation system.

## Current State

### What Exists

| Component | Status | Details |
|-----------|--------|---------|
| Company groups | Built | `companyGroup` table, `company.companyGroupId`, subsidiary hierarchy via `parentCompanyId` |
| Shared COA | Built | 4-digit accounts scoped to `companyGroupId`, parent-child tree with `isGroup`/`parentId` |
| IC accounts | Seeded | 1130 IC Receivables, 2020 IC Payables, 3200 Currency Translation Reserve, 4120 FX Gains, 7060 FX Losses |
| `consolidatedRate` | Schema only | Enum on `account` (Average/Current/Historical) — defined but never read by any logic |
| Elimination entity | Auto-created | `company.isEliminationEntity = true`, created when first subsidiary is added — no elimination logic |
| Journal system | Built | Immutable `journalLine` with `companyId` + `companyGroupId`, dimension tagging |
| `accountTreeBalances` | Built | Recursive CTE for tree rollup — **no per-company filter** |
| Currency | Partial | Single `exchangeRate` per currency, no rate types, no FX gain/loss recognition |
| Financial statements | None | No trial balance, P&L, or balance sheet pages |
| Intercompany | None | No IC transaction tagging, matching, or elimination |
| Consolidation | None | No consolidation engine, workflow, or reporting |

### Key Files

| File | Purpose |
|------|---------|
| `packages/database/supabase/migrations/20260228023426_company-groups.sql` | Company group architecture, RLS helpers |
| `packages/database/supabase/migrations/20260229000003_chart-of-accounts-tree.sql` | Account tree, `accountTreeBalances` RPC |
| `packages/database/supabase/migrations/20260228024512_dimensions.sql` | Dimension system |
| `packages/database/supabase/functions/lib/seed.data.ts` | Chart of accounts with IC accounts |
| `packages/database/supabase/functions/post-sales-invoice/index.ts` | Sales invoice posting |
| `packages/database/supabase/functions/post-purchase-invoice/index.ts` | Purchase invoice posting |
| `packages/database/supabase/functions/shared/get-posting-group.ts` | Account defaults fetcher |
| `apps/erp/app/modules/accounting/accounting.service.ts` | Accounting service layer |
| `apps/erp/app/modules/accounting/ui/useAccountingSubmodules.tsx` | Sidebar navigation |

## Phase Roadmap

Each phase delivers standalone value and builds on the previous.

```
Phase 1: Per-Company Financial Visibility          ✅ Done
    |
    v
Phase 2: Currency Translation                      ✅ Done
    |
    v
Phase 3: Intercompany Elimination                  ✅ Done
    |
    v
Phase 4: Consolidated Financial Statements         ⬜ Planned
    |
    v
Phase 5: Period-Close Enforcement                  ⬜ Planned
    |
    v
Phase 6: IC SO/PO Auto-Pairing                    ⬜ Planned
    |
    v
Phase 7: CTA-E (Elimination CTA)                  ⬜ Planned
    |
    v
Phase 8: IC Inventory Transfers                    ⬜ Planned
    |
    v
Phase 9: Period-Close Workflow UI                  ⬜ Planned
```

| Phase | Delivers | Key Additions |
|-------|----------|---------------|
| [Phase 1](./phase-1-per-company-financials.md) | Per-company trial balance, P&L, balance sheet | `accountTreeBalancesByCompany` RPC, 3 report pages |
| [Phase 2](./phase-2-currency-translation.md) | Foreign subsidiary currency translation | `exchangeRateHistory` table, translation RPC, exchange rate UI |
| [Phase 3](./phase-3-intercompany-elimination.md) | IC transaction matching and elimination | `intercompanyTransaction` table, modified posting functions, IC UI |
| [Phase 4](./phase-4-consolidated-statements.md) | Full group consolidation with workflow | `consolidationRun` tables, consolidation engine, multi-column reports |
| [Phase 5](./phase-5-period-close-enforcement.md) | Strict period-close enforcement | `Closed` status, trigger on `journal` INSERT, close/reopen service |
| [Phase 6](./phase-6-ic-so-po-auto-pairing.md) | Auto-generate SO from IC PO | `intercompanyPurchaseOrderId` on SO, status sync, pairing UI |
| [Phase 7](./phase-7-cta-elimination.md) | FX differences during elimination | CTA-E account, enhanced `generateEliminationEntries()` |
| [Phase 8](./phase-8-ic-inventory-transfers.md) | Cross-company inventory transfers | At-cost GL posting, at-markup via PO/SO workflow |
| [Phase 9](./phase-9-period-close-workflow.md) | Guided period-close checklist | Step-by-step close workflow, group-level status overview |

## Architecture Principles

1. **Immutable ledger** — all journal entries are append-only. Eliminations and CTA adjustments are new journal entries on the elimination entity, never modifications.
2. **Snapshot consolidation** — completed consolidation runs are snapshotted in `consolidationRunDetail` for auditability. Reports are served from snapshots, not recomputed.
3. **Existing RLS patterns** — all new tables use `get_company_groups_for_employee()` for SELECT and `get_company_groups_for_root_permission('accounting_*')` for mutations.
4. **Existing permissions** — `accounting_view`, `accounting_create`, `accounting_update` are sufficient. No new permission types needed.
5. **Group-scoped shared data** — accounts, currencies, dimensions, exchange rate history are all scoped to `companyGroupId`. Operational data (journals, consolidation runs) include `companyId` for per-entity tracking.
