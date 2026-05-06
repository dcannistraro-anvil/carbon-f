# Phase 4: Consolidated Financial Statements

## Goal

Bring together per-company balances, currency translation, and intercompany eliminations into consolidated financial statements with a formal consolidation workflow. This is the culmination phase that produces group-level trial balance, P&L, and balance sheet with full drill-down capability.

**Standalone value:** This is what the entire multi-entity architecture was built for — a single consolidated view of the group's financial position.

## Dependencies

- Phase 1 (per-company balances)
- Phase 2 (currency translation)
- Phase 3 (intercompany elimination)

## Database Changes

### 4a. New Table: `consolidationRun`

Represents a single consolidation execution for a specific period. Tracks workflow status and configuration.

```sql
CREATE TABLE "consolidationRun" (
  "id" TEXT NOT NULL DEFAULT id('crun'),
  "companyGroupId" TEXT NOT NULL,
  "accountingPeriodId" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'Draft',
  "targetCurrencyCode" TEXT NOT NULL,
  "periodStart" DATE NOT NULL,
  "periodEnd" DATE NOT NULL,
  "includedCompanyIds" TEXT[] NOT NULL,
  "eliminationJournalId" INTEGER,
  "translationJournalId" INTEGER,
  "notes" TEXT,
  "completedAt" TIMESTAMP WITH TIME ZONE,
  "completedBy" TEXT,
  "createdBy" TEXT NOT NULL,
  "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  "updatedBy" TEXT,
  "updatedAt" TIMESTAMP WITH TIME ZONE,

  CONSTRAINT "consolidationRun_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "consolidationRun_companyGroupId_fkey"
    FOREIGN KEY ("companyGroupId") REFERENCES "companyGroup"("id") ON DELETE CASCADE,
  CONSTRAINT "consolidationRun_completedBy_fkey"
    FOREIGN KEY ("completedBy") REFERENCES "user"("id"),
  CONSTRAINT "consolidationRun_createdBy_fkey"
    FOREIGN KEY ("createdBy") REFERENCES "user"("id"),
  CONSTRAINT "consolidationRun_status_check"
    CHECK ("status" IN ('Draft', 'In Progress', 'Completed', 'Reverted'))
);

CREATE INDEX "consolidationRun_companyGroupId_idx"
  ON "consolidationRun"("companyGroupId");
CREATE INDEX "consolidationRun_period_idx"
  ON "consolidationRun"("accountingPeriodId", "companyGroupId");

ALTER TABLE "consolidationRun" ENABLE ROW LEVEL SECURITY;
```

**RLS:**

```sql
CREATE POLICY "consolidationRun_select" ON "consolidationRun"
  FOR SELECT USING (
    "companyGroupId" = ANY (SELECT "get_company_groups_for_employee"())
  );

CREATE POLICY "consolidationRun_insert" ON "consolidationRun"
  FOR INSERT WITH CHECK (
    "companyGroupId" = ANY (SELECT "get_company_groups_for_root_permission"('accounting_create'))
  );

CREATE POLICY "consolidationRun_update" ON "consolidationRun"
  FOR UPDATE USING (
    "companyGroupId" = ANY (SELECT "get_company_groups_for_root_permission"('accounting_update'))
  );
```

### 4b. New Table: `consolidationRunDetail`

Snapshots per-company, per-account results for a consolidation run. Makes consolidated reports fast to load and auditable.

```sql
CREATE TABLE "consolidationRunDetail" (
  "id" TEXT NOT NULL DEFAULT id('crd'),
  "consolidationRunId" TEXT NOT NULL,
  "companyId" TEXT NOT NULL,
  "accountId" TEXT NOT NULL,
  "accountNumber" TEXT,
  "localCurrencyCode" TEXT NOT NULL,
  "localBalance" NUMERIC(19, 4) NOT NULL DEFAULT 0,
  "exchangeRate" NUMERIC(20, 8) NOT NULL DEFAULT 1,
  "translatedBalance" NUMERIC(19, 4) NOT NULL DEFAULT 0,
  "eliminationAmount" NUMERIC(19, 4) NOT NULL DEFAULT 0,
  "consolidatedBalance" NUMERIC(19, 4) NOT NULL DEFAULT 0,

  CONSTRAINT "consolidationRunDetail_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "consolidationRunDetail_consolidationRunId_fkey"
    FOREIGN KEY ("consolidationRunId") REFERENCES "consolidationRun"("id") ON DELETE CASCADE,
  CONSTRAINT "consolidationRunDetail_companyId_fkey"
    FOREIGN KEY ("companyId") REFERENCES "company"("id"),
  CONSTRAINT "consolidationRunDetail_accountId_fkey"
    FOREIGN KEY ("accountId") REFERENCES "account"("id")
);

CREATE INDEX "consolidationRunDetail_runId_idx"
  ON "consolidationRunDetail"("consolidationRunId");
CREATE INDEX "consolidationRunDetail_companyAccount_idx"
  ON "consolidationRunDetail"("consolidationRunId", "companyId", "accountId");

ALTER TABLE "consolidationRunDetail" ENABLE ROW LEVEL SECURITY;

-- RLS via parent consolidationRun
CREATE POLICY "consolidationRunDetail_select" ON "consolidationRunDetail"
  FOR SELECT USING (
    "consolidationRunId" IN (
      SELECT "id" FROM "consolidationRun"
      WHERE "companyGroupId" = ANY (SELECT "get_company_groups_for_employee"())
    )
  );

CREATE POLICY "consolidationRunDetail_insert" ON "consolidationRunDetail"
  FOR INSERT WITH CHECK (
    "consolidationRunId" IN (
      SELECT "id" FROM "consolidationRun"
      WHERE "companyGroupId" = ANY (SELECT "get_company_groups_for_root_permission"('accounting_create'))
    )
  );
```

### 4c. New RPC: `executeConsolidation`

```sql
CREATE OR REPLACE FUNCTION "executeConsolidation" (
  p_consolidation_run_id TEXT,
  p_user_id TEXT
)
RETURNS VOID
LANGUAGE "plpgsql"
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_run RECORD;
  v_company RECORD;
  v_elimination_company_id TEXT;
  v_target_currency TEXT;
BEGIN
  -- Load consolidation run configuration
  SELECT * INTO v_run
  FROM "consolidationRun"
  WHERE "id" = p_consolidation_run_id;

  IF v_run."status" != 'Draft' THEN
    RAISE EXCEPTION 'Consolidation run % is not in Draft status', p_consolidation_run_id;
  END IF;

  -- Update status to In Progress
  UPDATE "consolidationRun"
  SET "status" = 'In Progress', "updatedAt" = NOW(), "updatedBy" = p_user_id
  WHERE "id" = p_consolidation_run_id;

  v_target_currency := v_run."targetCurrencyCode";

  -- Find elimination entity
  SELECT "id" INTO v_elimination_company_id
  FROM "company"
  WHERE "companyGroupId" = v_run."companyGroupId"
    AND "isEliminationEntity" = true
  LIMIT 1;

  -- For each included company, snapshot balances
  FOR v_company IN
    SELECT c."id", c."baseCurrencyCode"
    FROM "company" c
    WHERE c."id" = ANY(v_run."includedCompanyIds")
      AND c."isEliminationEntity" = false
  LOOP
    -- Get translated balances for this company
    INSERT INTO "consolidationRunDetail" (
      "consolidationRunId", "companyId", "accountId", "accountNumber",
      "localCurrencyCode", "localBalance", "exchangeRate",
      "translatedBalance", "eliminationAmount", "consolidatedBalance"
    )
    SELECT
      p_consolidation_run_id,
      v_company."id",
      t."accountId",
      a."number",
      v_company."baseCurrencyCode",
      t."localBalance",
      t."exchangeRate",
      t."translatedBalance",
      0,  -- elimination amount filled in next step
      t."translatedBalance"  -- consolidated = translated before eliminations
    FROM "translateTrialBalance"(
      v_run."companyGroupId",
      v_company."id",
      v_target_currency,
      v_run."periodEnd",
      v_run."periodStart"
    ) t
    INNER JOIN "account" a ON a."id" = t."accountId";
  END LOOP;

  -- Add elimination entity balances (these ARE the elimination entries)
  IF v_elimination_company_id IS NOT NULL THEN
    INSERT INTO "consolidationRunDetail" (
      "consolidationRunId", "companyId", "accountId", "accountNumber",
      "localCurrencyCode", "localBalance", "exchangeRate",
      "translatedBalance", "eliminationAmount", "consolidatedBalance"
    )
    SELECT
      p_consolidation_run_id,
      v_elimination_company_id,
      b."accountId",
      a."number",
      v_target_currency,
      b."balanceAtDate",
      1,
      b."balanceAtDate",
      b."balanceAtDate",  -- entire balance is elimination
      0  -- does not contribute to consolidated (it's the offset)
    FROM "accountTreeBalancesByCompany"(
      v_run."companyGroupId",
      v_elimination_company_id,
      v_run."periodStart",
      v_run."periodEnd"
    ) b
    INNER JOIN "account" a ON a."id" = b."accountId"
    WHERE b."balanceAtDate" != 0;

    -- Apply elimination amounts to the consolidated balances
    UPDATE "consolidationRunDetail" crd
    SET
      "eliminationAmount" = elim."eliminationAmount",
      "consolidatedBalance" = crd."translatedBalance" + elim."eliminationAmount"
    FROM (
      SELECT
        "accountId",
        SUM("eliminationAmount") AS "eliminationAmount"
      FROM "consolidationRunDetail"
      WHERE "consolidationRunId" = p_consolidation_run_id
        AND "companyId" = v_elimination_company_id
      GROUP BY "accountId"
    ) elim
    WHERE crd."consolidationRunId" = p_consolidation_run_id
      AND crd."accountId" = elim."accountId"
      AND crd."companyId" != v_elimination_company_id;
  END IF;

  -- Mark completed
  UPDATE "consolidationRun"
  SET
    "status" = 'Completed',
    "completedAt" = NOW(),
    "completedBy" = p_user_id,
    "updatedAt" = NOW(),
    "updatedBy" = p_user_id
  WHERE "id" = p_consolidation_run_id;
END;
$$;
```

### Migration

Single migration file: `YYYYMMDDHHMMSS_consolidation-run.sql`

Contains: `consolidationRun` table, `consolidationRunDetail` table, RLS policies, `executeConsolidation` RPC.

## Backend / Service Layer

### New File: `apps/erp/app/modules/accounting/consolidation.service.ts`

```typescript
export async function getConsolidationRuns(
  client: SupabaseClient<Database>,
  companyGroupId: string,
  args?: { status?: string }
)

export async function getConsolidationRun(
  client: SupabaseClient<Database>,
  runId: string
)

export async function createConsolidationRun(
  client: SupabaseClient<Database>,
  input: {
    companyGroupId: string;
    accountingPeriodId: string;
    targetCurrencyCode: string;
    periodStart: string;
    periodEnd: string;
    includedCompanyIds: string[];
    notes?: string;
    createdBy: string;
  }
)

export async function executeConsolidation(
  client: SupabaseClient<Database>,
  runId: string,
  userId: string
)

export async function revertConsolidation(
  client: SupabaseClient<Database>,
  runId: string,
  userId: string
)
// Sets status to 'Reverted', does NOT delete detail rows (audit trail)

export async function getConsolidatedTrialBalance(
  client: SupabaseClient<Database>,
  runId: string
)
// Aggregates consolidationRunDetail by accountId, returns consolidated totals

export async function getConsolidatedBalanceSheet(
  client: SupabaseClient<Database>,
  runId: string
)
// Same as trial balance but filtered to Balance Sheet accounts, in tree structure

export async function getConsolidatedIncomeStatement(
  client: SupabaseClient<Database>,
  runId: string
)
// Same but filtered to Income Statement accounts

export async function getConsolidationDrillDown(
  client: SupabaseClient<Database>,
  runId: string,
  accountId: string
)
// Returns per-company breakdown for one account:
// companyName, localBalance, exchangeRate, translatedBalance, eliminationAmount, consolidatedBalance
```

### New File: `apps/erp/app/modules/accounting/consolidation.models.ts`

```typescript
export const consolidationRunValidator = z.object({
  accountingPeriodId: z.string(),
  targetCurrencyCode: z.string().min(3).max(3),
  periodStart: z.string(),
  periodEnd: z.string(),
  includedCompanyIds: z.string().array().min(1),
  notes: z.string().optional(),
});

export type ConsolidationRunStatus = "Draft" | "In Progress" | "Completed" | "Reverted";
```

## UI

### New Routes

| Route file | URL path | Purpose |
|---|---|---|
| `routes/x+/accounting+/consolidation.tsx` | `/x/accounting/consolidation` | List of consolidation runs |
| `routes/x+/accounting+/consolidation.new.tsx` | `/x/accounting/consolidation/new` | Create new run |
| `routes/x+/accounting+/consolidation.$runId.tsx` | `/x/accounting/consolidation/:runId` | View/execute a run |
| `routes/x+/accounting+/consolidation.$runId.trial-balance.tsx` | `.../trial-balance` | Consolidated trial balance |
| `routes/x+/accounting+/consolidation.$runId.balance-sheet.tsx` | `.../balance-sheet` | Consolidated balance sheet |
| `routes/x+/accounting+/consolidation.$runId.income-statement.tsx` | `.../income-statement` | Consolidated P&L |

### Sidebar

Add under "Manage" group:

```typescript
{ name: "Consolidation", to: path.to.consolidation }
```

### New Components

| Component | Location | Purpose |
|---|---|---|
| `ConsolidationRunList` | `modules/accounting/ui/Consolidation/ConsolidationRunList.tsx` | Table of runs with status badges (Draft/In Progress/Completed/Reverted) |
| `ConsolidationRunForm` | `modules/accounting/ui/Consolidation/ConsolidationRunForm.tsx` | Period selector, company checklist, target currency |
| `ConsolidationWorkflow` | `modules/accounting/ui/Consolidation/ConsolidationWorkflow.tsx` | Step-by-step workflow (see below) |
| `ConsolidatedReportTable` | `modules/accounting/ui/Consolidation/ConsolidatedReportTable.tsx` | Multi-column table with per-company columns |
| `DrillDownDrawer` | `modules/accounting/ui/Consolidation/DrillDownDrawer.tsx` | Slide-out showing per-company breakdown for one account |

### Consolidation Workflow

The `ConsolidationWorkflow` component on the run detail page presents a stepper:

```
Step 1: Configuration
  - Period, target currency, included companies (set at creation, read-only here)
  - Validation: all subsidiaries have closed or active accounting periods

Step 2: Review Company Balances
  - Show each company's trial balance side-by-side
  - Highlight any companies with unbalanced trial balances

Step 3: Currency Translation (if multi-currency group)
  - Show translated vs local balances for foreign subsidiaries
  - Show CTA amount per subsidiary
  - Link to Exchange Rates page if rates are missing

Step 4: Intercompany Elimination
  - Show IC matching status
  - "Run Matching" button if unmatched transactions exist
  - "Generate Eliminations" button
  - Show elimination journal entries

Step 5: Execute & Finalize
  - "Execute Consolidation" button
  - Snapshots all numbers into consolidationRunDetail
  - Shows consolidated trial balance preview
  - "Finalize" marks run as Completed
```

### Consolidated Report Table (Multi-Column)

The consolidated financial statements show a multi-column layout:

```
Account         | Company A | Company B | Eliminations | Consolidated
─────────────────────────────────────────────────────────────────────
4010 Sales      | $500,000  | $300,000  | ($50,000)    | $750,000
5010 COGS       | $200,000  | $150,000  | ($50,000)    | $300,000
...
```

Clicking any cell opens the `DrillDownDrawer` showing:

```
Account: 4010 Sales - Consolidated: $750,000

Company       | Local    | Rate   | Translated | Elimination | Consolidated
──────────────────────────────────────────────────────────────────────────
Company A     | $500,000 | 1.0000 | $500,000   | ($50,000)   | $450,000
Company B     | €250,000 | 1.2000 | $300,000   | $0          | $300,000
Elimination   |          |        |            |             |
──────────────────────────────────────────────────────────────────────────
Total         |          |        | $800,000   | ($50,000)   | $750,000
```

## Data Flow

```
Finance controller creates consolidation run
  - Selects period: Q4 2026
  - Selects companies: Company A, Company B
  - Target currency: USD
    |
    v
System validates:
  - All subsidiaries have accounting periods covering the date range
  - Exchange rates exist for foreign currencies (if applicable)
  - IC matching has been run (warns if unmatched exist)
    |
    v
User clicks "Execute Consolidation"
    |
    v
executeConsolidation RPC:
  For each company:
    1. Get per-company trial balance (Phase 1)
    2. Translate to target currency (Phase 2)
    3. Snapshot into consolidationRunDetail
  Then:
    4. Include elimination entity balances
    5. Apply elimination amounts to consolidated totals
    6. Mark run as Completed
    |
    v
User views consolidated reports
  - Trial balance, balance sheet, P&L served from snapshot
  - Click any number → drill-down drawer shows per-company breakdown
    |
    v
Reports are immutable (served from consolidationRunDetail snapshot)
  - Can be compared across periods
  - Audit trail preserved even if underlying data changes
```

## Acceptance Criteria

- [ ] Consolidation run captures period, target currency, and selected companies
- [ ] Only companies in the same `companyGroupId` can be included
- [ ] Consolidation engine correctly sums per-company translated balances
- [ ] Elimination entries from Phase 3 are correctly applied
- [ ] CTA from Phase 2 appears on the consolidated balance sheet under account 3200
- [ ] Consolidated balance sheet balances: Assets = Liabilities + Equity
- [ ] Consolidated trial balance: total debits = total credits
- [ ] Drill-down from any consolidated line shows per-company breakdown with:
  - Local balance, exchange rate, translated balance, elimination amount, consolidated balance
- [ ] Multi-column report shows each company's contribution
- [ ] Completed consolidation runs are immutable (snapshotted in `consolidationRunDetail`)
- [ ] Consolidation can be reverted (sets status to `Reverted`, preserves data for audit)
- [ ] Only one active (non-Reverted) consolidation run per period per company group
- [ ] Workflow enforces proper sequencing (rates entered → IC matched → eliminations generated → consolidated)
- [ ] Empty/missing data handled gracefully (company with no transactions shows zero)
- [ ] Consolidation run list shows history with status, period, who ran it, when
