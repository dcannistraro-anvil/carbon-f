# Phase 1: Per-Company Financial Visibility

## Goal

Enable users to view trial balance, P&L, and balance sheet at the individual company level. Today `accountTreeBalances` sums journal lines across ALL companies in a group with no way to filter by company. This phase fixes that foundational gap and delivers the first financial reporting pages.

**Standalone value:** Single-entity companies need these reports regardless of whether consolidation is ever used.

## Dependencies

None — this phase uses only existing tables and adds new RPC functions.

## Database Changes

### 1a. New RPC: `accountTreeBalancesByCompany`

This extends the existing `accountTreeBalances` with an optional `p_company_id` filter. When NULL, it behaves identically to the existing function (aggregate across all companies).

```sql
CREATE OR REPLACE FUNCTION "accountTreeBalancesByCompany" (
  p_company_group_id TEXT,
  p_company_id TEXT DEFAULT NULL,
  from_date DATE DEFAULT (now() - INTERVAL '100 year'),
  to_date DATE DEFAULT now()
)
RETURNS TABLE (
  "accountId" TEXT,
  "balance" NUMERIC(19, 4),
  "balanceAtDate" NUMERIC(19, 4),
  "netChange" NUMERIC(19, 4)
)
LANGUAGE "plpgsql"
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE "accountTree" AS (
    SELECT a."id", a."id" AS "rootId", a."parentId", a."isGroup"
    FROM "account" a
    WHERE a."companyGroupId" = p_company_group_id AND a."active" = true
    UNION ALL
    SELECT a."id", at."rootId", a."parentId", a."isGroup"
    FROM "account" a
    INNER JOIN "accountTree" at ON a."parentId" = at."id"
    WHERE a."companyGroupId" = p_company_group_id AND a."active" = true
  ),
  "leafBalances" AS (
    SELECT
      a."id" AS "accountId",
      COALESCE(SUM(jl."amount"), 0) AS "balance",
      COALESCE(SUM(CASE WHEN j."postingDate" <= to_date THEN jl."amount" ELSE 0 END), 0) AS "balanceAtDate",
      COALESCE(SUM(CASE WHEN j."postingDate" >= from_date AND j."postingDate" <= to_date THEN jl."amount" ELSE 0 END), 0) AS "netChange"
    FROM "account" a
    LEFT JOIN "journalLine" jl ON jl."accountNumber" = a."number"
      AND jl."companyGroupId" = a."companyGroupId"
      AND (p_company_id IS NULL OR jl."companyId" = p_company_id)
    LEFT JOIN "journal" j ON j."id" = jl."journalId"
    WHERE a."isGroup" = false
      AND a."companyGroupId" = p_company_group_id
      AND a."active" = true
    GROUP BY a."id"
  )
  SELECT
    at."rootId" AS "accountId",
    COALESCE(SUM(lb."balance"), 0) AS "balance",
    COALESCE(SUM(lb."balanceAtDate"), 0) AS "balanceAtDate",
    COALESCE(SUM(lb."netChange"), 0) AS "netChange"
  FROM "accountTree" at
  LEFT JOIN "leafBalances" lb ON lb."accountId" = at."id"
  WHERE at."isGroup" = false OR at."rootId" = at."id"
  GROUP BY at."rootId";
END;
$$;
```

**Key difference from existing `accountTreeBalances`:** The `AND (p_company_id IS NULL OR jl."companyId" = p_company_id)` clause in `leafBalances` enables per-company filtering while preserving the aggregate behavior when no company is specified.

### 1b. New RPC: `trialBalance`

Returns a flat list of leaf accounts with debit/credit split based on normal balance direction.

```sql
CREATE OR REPLACE FUNCTION "trialBalance" (
  p_company_group_id TEXT,
  p_company_id TEXT DEFAULT NULL,
  from_date DATE DEFAULT (now() - INTERVAL '100 year'),
  to_date DATE DEFAULT now()
)
RETURNS TABLE (
  "accountId" TEXT,
  "accountNumber" TEXT,
  "accountName" TEXT,
  "class" "glAccountClass",
  "incomeBalance" "glIncomeBalance",
  "debitBalance" NUMERIC(19, 4),
  "creditBalance" NUMERIC(19, 4),
  "netChange" NUMERIC(19, 4)
)
LANGUAGE "plpgsql"
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    a."id" AS "accountId",
    a."number" AS "accountNumber",
    a."name" AS "accountName",
    a."class",
    a."incomeBalance",
    CASE
      WHEN a."class" IN ('Asset', 'Expense') AND b."balanceAtDate" > 0 THEN b."balanceAtDate"
      WHEN a."class" IN ('Liability', 'Equity', 'Revenue') AND b."balanceAtDate" < 0 THEN ABS(b."balanceAtDate")
      ELSE 0
    END AS "debitBalance",
    CASE
      WHEN a."class" IN ('Liability', 'Equity', 'Revenue') AND b."balanceAtDate" > 0 THEN b."balanceAtDate"
      WHEN a."class" IN ('Asset', 'Expense') AND b."balanceAtDate" < 0 THEN ABS(b."balanceAtDate")
      ELSE 0
    END AS "creditBalance",
    b."netChange"
  FROM "account" a
  INNER JOIN "accountTreeBalancesByCompany"(p_company_group_id, p_company_id, from_date, to_date) b
    ON b."accountId" = a."id"
  WHERE a."isGroup" = false
    AND a."companyGroupId" = p_company_group_id
    AND (b."balanceAtDate" != 0 OR b."netChange" != 0)
  ORDER BY a."number";
END;
$$;
```

### Migration

Single migration file: `YYYYMMDDHHMMSS_per-company-balance-rpc.sql`

No new tables. No schema changes. Just the two new RPC functions above.

## Backend / Service Layer

### `apps/erp/app/modules/accounting/accounting.service.ts`

Add new service functions:

```typescript
export async function getTrialBalance(
  client: SupabaseClient<Database>,
  companyGroupId: string,
  companyId: string | null,
  args: { startDate: string | null; endDate: string | null }
) {
  return client.rpc("trialBalance", {
    p_company_group_id: companyGroupId,
    p_company_id: companyId,
    from_date: args.startDate ?? getDateNYearsAgo(50),
    to_date: args.endDate ?? today(getLocalTimeZone()),
  });
}

export async function getBalanceSheet(
  client: SupabaseClient<Database>,
  companyGroupId: string,
  companyId: string | null,
  args: { asOfDate: string | null }
) {
  const asOf = args.asOfDate ?? today(getLocalTimeZone());
  return client.rpc("accountTreeBalancesByCompany", {
    p_company_group_id: companyGroupId,
    p_company_id: companyId,
    from_date: "1900-01-01",
    to_date: asOf,
  });
  // Filter to incomeBalance = 'Balance Sheet' in the loader/component
}

export async function getIncomeStatement(
  client: SupabaseClient<Database>,
  companyGroupId: string,
  companyId: string | null,
  args: { startDate: string | null; endDate: string | null }
) {
  return client.rpc("accountTreeBalancesByCompany", {
    p_company_group_id: companyGroupId,
    p_company_id: companyId,
    from_date: args.startDate ?? getDateNYearsAgo(1),
    to_date: args.endDate ?? today(getLocalTimeZone()),
  });
  // Filter to incomeBalance = 'Income Statement' in the loader/component
}
```

For the balance sheet and income statement, the loader should also fetch the full account tree (accounts with parent-child relationships) and join with balances to build the hierarchical display.

## UI

### New Routes

| Route file | URL path | Purpose |
|---|---|---|
| `routes/x+/accounting+/trial-balance.tsx` | `/x/accounting/trial-balance` | Trial balance report |
| `routes/x+/accounting+/balance-sheet.tsx` | `/x/accounting/balance-sheet` | Balance sheet |
| `routes/x+/accounting+/income-statement.tsx` | `/x/accounting/income-statement` | Income statement / P&L |

### New Sidebar Group

In `useAccountingSubmodules.tsx`, add a "Reports" group:

```typescript
{
  name: "Reports",
  routes: [
    { name: "Trial Balance", to: path.to.trialBalance },
    { name: "Balance Sheet", to: path.to.balanceSheet },
    { name: "Income Statement", to: path.to.incomeStatement },
  ]
}
```

### New Components

| Component | Location | Purpose |
|---|---|---|
| `TrialBalanceTable` | `modules/accounting/ui/Reports/TrialBalanceTable.tsx` | Tabular debit/credit display with totals row |
| `BalanceSheetTree` | `modules/accounting/ui/Reports/BalanceSheetTree.tsx` | Tree-structured BS using same collapsible pattern as `ChartOfAccountsTree` |
| `IncomeStatementTree` | `modules/accounting/ui/Reports/IncomeStatementTree.tsx` | Tree-structured P&L |
| `ReportFilters` | `modules/accounting/ui/Reports/ReportFilters.tsx` | Shared filter bar: company selector, date range |
| `CompanySelector` | `modules/accounting/ui/Reports/CompanySelector.tsx` | Dropdown of companies in the group, with "All Companies" aggregated option |

### Route Loader Pattern

Each report page:
1. Calls `requirePermissions` to get `companyId` and `companyGroupId`
2. Fetches the list of companies in the group (for the CompanySelector)
3. Reads URL search params: `?companyId=...&startDate=...&endDate=...`
4. Calls the appropriate service function
5. Returns data to the component

CompanySelector triggers navigation with updated search params (no form submission, just URL-based filtering).

## Data Flow

```
User navigates to /x/accounting/trial-balance
    |
    v
Loader reads ?companyId=X&startDate=...&endDate=...
    |
    v
Loader calls getTrialBalance(client, companyGroupId, companyId, dates)
    |
    v
Service calls client.rpc("trialBalance", { p_company_group_id, p_company_id, from_date, to_date })
    |
    v
RPC filters journalLine by companyId, groups by account, splits debit/credit
    |
    v
UI renders TrialBalanceTable with totals row
    |
    v
User changes company in CompanySelector → URL updates → loader refetches
```

## Acceptance Criteria

- [ ] `accountTreeBalancesByCompany` RPC returns correct balances when filtered to a single company
- [ ] `accountTreeBalancesByCompany` with `p_company_id = NULL` returns the same results as the existing `accountTreeBalances`
- [ ] Trial balance page renders with debit and credit columns
- [ ] Total debits equal total credits on the trial balance
- [ ] Balance sheet shows Assets = Liabilities + Equity
- [ ] Income statement shows Revenue - Expenses = Net Income
- [ ] Company selector dropdown appears on all three report pages
- [ ] Selecting a different company re-filters the report correctly
- [ ] "All Companies" option shows aggregated group-level balances
- [ ] Reports respect date range filters
- [ ] Empty state shown when no journal entries exist
