# Plan: accountDefault stores account IDs, not numbers

## Context

The `accountDefault` table has 35+ columns that store account **numbers** (like "4010", "5010"). These require composite FKs with `companyGroupId` to resolve to the correct account. Edge functions then call `resolveAccountIds()` to translate numbers → IDs before writing journal lines.

**Goal:** Make `accountDefault` store account **IDs** directly. This:
- Eliminates `companyGroupId` from `accountDefault` (no longer needed for FK resolution)
- Eliminates the `resolveAccountIds` helper in edge functions
- Makes the data flow simpler: edge function reads accountDefault → gets IDs → writes to journalLine

## Phase 1: Migrations (DB schema)

### 1.1 Company-groups migration — accountDefault section
- [x] Replace composite FKs with simple FKs `("col") → account("id")`
- [x] Add DO block to backfill all 38 account columns from numbers to IDs
- [x] Remove `companyGroupId` column addition from accountDefault

### 1.2 Reset-chart-of-accounts migration
- [x] Move accountDefault INSERT inside DO block to use `key_to_id` for IDs
- [x] Remove `companyGroupId` from INSERT column list
- [x] Convert Phase 6 FKs from composite to simple
- [x] Add `currencyTranslationAccount` column in Phase 2.5
- [x] Add accountId NULL updates to Phase 2

### 1.3 Intercompany tracking migration
- [x] Write `accountId` (from `jl."accountId"`) in `generateEliminationEntries`

### 1.4 Make journalLine.accountNumber nullable
- [x] Added `ALTER COLUMN "accountNumber" DROP NOT NULL` in company-groups migration

## Phase 2: Edge functions

- [x] Remove resolveAccountIds from post-purchase-invoice
- [x] Remove resolveAccountIds from post-sales-invoice
- [x] Remove resolveAccountIds from post-receipt
- [x] Delete resolve-account-ids.ts
- [x] Remove accountNumber from journal line pushes (would contain IDs, not numbers)

## Phase 3: Seed data

- [x] seed-company/index.ts: resolve account numbers to IDs via accountIdByKey map
- [x] seed-dev.ts: resolve account numbers to IDs via resolveAccountId helper
- [x] Remove companyGroupId from accountDefault inserts in both seed paths

## Phase 4: App layer

- [x] AccountDefaultsForm: changed Combobox options from `value: c.number` to `value: c.id`
- [x] Verified accounting.service.ts works with IDs (getAccountsList already selects id)
- [x] Verified validators use z.string() — works for both numbers and IDs

## Phase 5: Verification

- [ ] Rebuild database — all migrations apply cleanly
- [ ] Regenerate types — `npm run db:types` in packages/database
- [ ] Type check changed files
- [ ] End-to-end testing
