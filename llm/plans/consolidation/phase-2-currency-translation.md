# Phase 2: Currency Translation

## Goal

Translate foreign subsidiary financials into the parent company's reporting currency. When a subsidiary uses a different `baseCurrencyCode` than the parent, its balances must be translated using the appropriate exchange rates before consolidation.

This phase introduces exchange rate types, translation logic, and the Currency Translation Adjustment (CTA) calculation that flows into the `currencyTranslationAccount` default account.

**Standalone value:** Even without full consolidation, finance teams need to see subsidiary financials expressed in the parent's currency for comparison and reporting.

## Dependencies

- Phase 1 must be complete (`accountTreeBalancesByCompany` RPC and per-company filtering)

## Accounting Standard

This follows **IAS 21 / ASC 830** conventions:

| Account type | Rate to use | `consolidatedRate` value |
|---|---|---|
| Balance sheet (assets, liabilities) | Closing rate at period end | `Current` |
| Income statement (revenue, expenses) | Average rate for the period | `Average` |
| Equity accounts | Historical rate (rate at time of investment/event) | `Historical` |

The difference between translated assets and translated (liabilities + equity) is the **Currency Translation Adjustment (CTA)**, which flows to the `currencyTranslationAccount` from `accountDefault`.

## Database Changes

### 2a. New Enum: `exchangeRateType`

```sql
CREATE TYPE "exchangeRateType" AS ENUM (
  'Spot',
  'Average',
  'Closing',
  'Historical'
);
```

### 2b. New Table: `exchangeRateHistory`

Stores historical exchange rates by type and date, scoped to the company group.

```sql
CREATE TABLE "exchangeRateHistory" (
  "id" TEXT NOT NULL DEFAULT id('exr'),
  "currencyCode" TEXT NOT NULL,
  "rateType" "exchangeRateType" NOT NULL,
  "rate" NUMERIC(20, 8) NOT NULL,
  "effectiveDate" DATE NOT NULL,
  "companyGroupId" TEXT NOT NULL,
  "createdBy" TEXT NOT NULL,
  "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  "updatedBy" TEXT,
  "updatedAt" TIMESTAMP WITH TIME ZONE,

  CONSTRAINT "exchangeRateHistory_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "exchangeRateHistory_companyGroupId_fkey"
    FOREIGN KEY ("companyGroupId") REFERENCES "companyGroup"("id") ON DELETE CASCADE,
  CONSTRAINT "exchangeRateHistory_currencyCode_fkey"
    FOREIGN KEY ("currencyCode", "companyGroupId") REFERENCES "currency"("code", "companyGroupId"),
  CONSTRAINT "exchangeRateHistory_createdBy_fkey"
    FOREIGN KEY ("createdBy") REFERENCES "user"("id"),
  CONSTRAINT "exchangeRateHistory_rate_check" CHECK ("rate" > 0),
  CONSTRAINT "exchangeRateHistory_unique"
    UNIQUE ("currencyCode", "rateType", "effectiveDate", "companyGroupId")
);

CREATE INDEX "exchangeRateHistory_lookup_idx"
  ON "exchangeRateHistory"("currencyCode", "companyGroupId", "rateType", "effectiveDate" DESC);
```

**RLS policies** (same pattern as `currency` table):

```sql
CREATE POLICY "exchangeRateHistory_select" ON "exchangeRateHistory"
  FOR SELECT USING (
    "companyGroupId" = ANY (SELECT "get_company_groups_for_employee"())
  );

CREATE POLICY "exchangeRateHistory_insert" ON "exchangeRateHistory"
  FOR INSERT WITH CHECK (
    "companyGroupId" = ANY (SELECT "get_company_groups_for_root_permission"('accounting_create'))
  );

CREATE POLICY "exchangeRateHistory_update" ON "exchangeRateHistory"
  FOR UPDATE USING (
    "companyGroupId" = ANY (SELECT "get_company_groups_for_root_permission"('accounting_update'))
  );

CREATE POLICY "exchangeRateHistory_delete" ON "exchangeRateHistory"
  FOR DELETE USING (
    "companyGroupId" = ANY (SELECT "get_company_groups_for_root_permission"('accounting_delete'))
  );

ALTER TABLE "exchangeRateHistory" ENABLE ROW LEVEL SECURITY;
```

### 2c. Populate `consolidatedRate` on Existing Accounts

The `consolidatedRate` column already exists on `account` (defined in migration `20230330024715_accounts.sql`) but is nullable and likely NULL for most accounts. This migration sets defaults based on IAS 21 and makes the column required:

```sql
-- Set defaults based on account classification
UPDATE "account"
SET "consolidatedRate" = CASE
  WHEN "incomeBalance" = 'Income Statement' THEN 'Average'::"glConsolidatedRate"
  WHEN "class" = 'Equity' THEN 'Historical'::"glConsolidatedRate"
  ELSE 'Current'::"glConsolidatedRate"
END
WHERE "consolidatedRate" IS NULL;

-- Make non-nullable with sensible default
ALTER TABLE "account" ALTER COLUMN "consolidatedRate" SET NOT NULL;
ALTER TABLE "account" ALTER COLUMN "consolidatedRate" SET DEFAULT 'Current'::"glConsolidatedRate";
```

Also update `seed.data.ts` to include `consolidatedRate` on each account entry so new company groups get the correct defaults.

### 2d. Add `currencyTranslationAccount` to `accountDefault`

Add a new column to `accountDefault` so the CTA account is dynamically configurable rather than hardcoded. Backfill existing rows with "3200" and add FK constraint. Also add `currencyTranslationAccount: "3200"` to `accountDefaults` in `seed.data.ts`, the validator in `accounting.models.ts`, and the UI form in `AccountDefaultsForm.tsx`.

**Note:** This was already implemented as part of the migration and seed data changes.

### 2e. New RPC: `translateTrialBalance`

```sql
CREATE OR REPLACE FUNCTION "translateTrialBalance" (
  p_company_group_id TEXT,
  p_company_id TEXT,
  p_target_currency TEXT,
  p_period_end DATE,
  p_period_start DATE DEFAULT NULL
)
RETURNS TABLE (
  "accountId" TEXT,
  "localBalance" NUMERIC(19, 4),
  "exchangeRate" NUMERIC(20, 8),
  "translatedBalance" NUMERIC(19, 4),
  "translationDifference" NUMERIC(19, 4)
)
LANGUAGE "plpgsql"
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_source_currency TEXT;
  v_closing_rate NUMERIC(20, 8);
  v_average_rate NUMERIC(20, 8);
  v_historical_rate NUMERIC(20, 8);
  v_total_translated NUMERIC(19, 4) := 0;
  v_total_translated_equity NUMERIC(19, 4) := 0;
BEGIN
  -- Get the subsidiary's base currency
  SELECT "baseCurrencyCode" INTO v_source_currency
  FROM "company" WHERE "id" = p_company_id;

  -- If same currency, no translation needed
  IF v_source_currency = p_target_currency THEN
    RETURN QUERY
    SELECT
      b."accountId",
      b."balanceAtDate" AS "localBalance",
      1.0::NUMERIC(20, 8) AS "exchangeRate",
      b."balanceAtDate" AS "translatedBalance",
      0::NUMERIC(19, 4) AS "translationDifference"
    FROM "accountTreeBalancesByCompany"(p_company_group_id, p_company_id, p_period_start, p_period_end) b;
    RETURN;
  END IF;

  -- Look up rates from exchangeRateHistory
  SELECT "rate" INTO v_closing_rate
  FROM "exchangeRateHistory"
  WHERE "currencyCode" = v_source_currency
    AND "companyGroupId" = p_company_group_id
    AND "rateType" = 'Closing'
    AND "effectiveDate" <= p_period_end
  ORDER BY "effectiveDate" DESC LIMIT 1;

  SELECT "rate" INTO v_average_rate
  FROM "exchangeRateHistory"
  WHERE "currencyCode" = v_source_currency
    AND "companyGroupId" = p_company_group_id
    AND "rateType" = 'Average'
    AND "effectiveDate" <= p_period_end
  ORDER BY "effectiveDate" DESC LIMIT 1;

  SELECT "rate" INTO v_historical_rate
  FROM "exchangeRateHistory"
  WHERE "currencyCode" = v_source_currency
    AND "companyGroupId" = p_company_group_id
    AND "rateType" = 'Historical'
    AND "effectiveDate" <= p_period_end
  ORDER BY "effectiveDate" DESC LIMIT 1;

  -- Default to closing rate if specific types not found
  v_average_rate := COALESCE(v_average_rate, v_closing_rate, 1);
  v_historical_rate := COALESCE(v_historical_rate, v_closing_rate, 1);
  v_closing_rate := COALESCE(v_closing_rate, 1);

  RETURN QUERY
  SELECT
    b."accountId",
    b."balanceAtDate" AS "localBalance",
    CASE a."consolidatedRate"
      WHEN 'Current' THEN v_closing_rate
      WHEN 'Average' THEN v_average_rate
      WHEN 'Historical' THEN v_historical_rate
    END AS "exchangeRate",
    ROUND(b."balanceAtDate" * CASE a."consolidatedRate"
      WHEN 'Current' THEN v_closing_rate
      WHEN 'Average' THEN v_average_rate
      WHEN 'Historical' THEN v_historical_rate
    END, 4) AS "translatedBalance",
    0::NUMERIC(19, 4) AS "translationDifference"  -- CTA calculated by caller
  FROM "accountTreeBalancesByCompany"(p_company_group_id, p_company_id, p_period_start, p_period_end) b
  INNER JOIN "account" a ON a."id" = b."accountId"
  WHERE a."isGroup" = false;
END;
$$;
```

**CTA calculation:** The caller (consolidation service) computes CTA as:
```
CTA = Total Translated Assets - Total Translated (Liabilities + Equity)
```
This amount is assigned to the `currencyTranslationAccount` from `accountDefault` (defaults to 3200 - Reserves (Currency Translation)).

### Migration

Single migration file: `YYYYMMDDHHMMSS_exchange-rate-history.sql`

Contains: the enum, the table, RLS policies, the `consolidatedRate` population, and the `translateTrialBalance` RPC.

## Backend / Service Layer

### New File: `apps/erp/app/modules/accounting/currency-translation.service.ts`

```typescript
export async function getExchangeRateHistory(
  client: SupabaseClient<Database>,
  companyGroupId: string,
  args: {
    currencyCode?: string;
    rateType?: ExchangeRateType;
    startDate?: string;
    endDate?: string;
  }
)

export async function upsertExchangeRate(
  client: SupabaseClient<Database>,
  companyGroupId: string,
  input: {
    currencyCode: string;
    rateType: ExchangeRateType;
    rate: number;
    effectiveDate: string;
  }
)

export async function deleteExchangeRate(
  client: SupabaseClient<Database>,
  rateId: string
)

export async function translateCompanyBalances(
  client: SupabaseClient<Database>,
  companyGroupId: string,
  companyId: string,
  targetCurrency: string,
  periodEnd: string,
  periodStart?: string
)
```

### New File: `apps/erp/app/modules/accounting/currency-translation.models.ts`

```typescript
export const exchangeRateValidator = z.object({
  currencyCode: z.string().min(3).max(3),
  rateType: z.enum(["Spot", "Average", "Closing", "Historical"]),
  rate: zfd.numeric(z.number().positive()),
  effectiveDate: z.string(),
});

export type ExchangeRateType = "Spot" | "Average" | "Closing" | "Historical";
```

### Update: `seed.data.ts`

Add `consolidatedRate` to each account in the seed data:

```typescript
// Balance sheet accounts get "Current" (closing rate)
{ key: "1010", number: "1010", name: "Bank - Cash", ..., consolidatedRate: "Current" },

// Income statement accounts get "Average"
{ key: "4010", number: "4010", name: "Sales", ..., consolidatedRate: "Average" },

// Equity accounts get "Historical"
{ key: "3100", number: "3100", name: "Retained Earnings", ..., consolidatedRate: "Historical" },
```

## UI

### New Routes

| Route file | URL path | Purpose |
|---|---|---|
| `routes/x+/accounting+/exchange-rates.tsx` | `/x/accounting/exchange-rates` | Exchange rate history table |
| `routes/x+/accounting+/exchange-rates.new.tsx` | `/x/accounting/exchange-rates/new` | Add new rate entry |
| `routes/x+/accounting+/exchange-rates.$rateId.tsx` | `/x/accounting/exchange-rates/:rateId` | Edit rate entry |
| `routes/x+/accounting+/exchange-rates.delete.$rateId.tsx` | Delete action | Delete rate entry |

### Sidebar

Add under "Configure" group in `useAccountingSubmodules.tsx`:

```typescript
{ name: "Exchange Rates", to: path.to.exchangeRates }
```

### New Components

| Component | Location | Purpose |
|---|---|---|
| `ExchangeRateTable` | `modules/accounting/ui/ExchangeRates/ExchangeRateTable.tsx` | Filterable table of rates by currency, type, date |
| `ExchangeRateForm` | `modules/accounting/ui/ExchangeRates/ExchangeRateForm.tsx` | Form for adding/editing a rate |

### Enhance Phase 1 Report Pages

When viewing a foreign subsidiary (where `company.baseCurrencyCode != parentCompany.baseCurrencyCode`):

1. Add a "Show Translated" toggle to `ReportFilters`
2. When enabled, show two columns: "Local Currency" and "Translated ({parentCurrency})"
3. At the bottom of the balance sheet, show a "Currency Translation Adjustment" row mapped to the `currencyTranslationAccount` from `accountDefault`

## Data Flow

```
Finance admin enters exchange rates
    |
    v
exchangeRateHistory table (Closing, Average, Historical rates per currency per date)
    |
    v
User views foreign subsidiary balance sheet with "Show Translated" enabled
    |
    v
Loader calls translateCompanyBalances(companyGroupId, companyId, parentCurrency, periodEnd)
    |
    v
RPC:
  1. Gets local balances via accountTreeBalancesByCompany
  2. Looks up rates by account.consolidatedRate type
  3. Multiplies each balance by the appropriate rate
    |
    v
Service computes CTA = translated assets - translated (liabilities + equity)
    |
    v
UI renders dual-column report with CTA row on balance sheet
```

## Acceptance Criteria

- [ ] Exchange rate history page allows CRUD for Spot, Average, Closing, and Historical rates
- [ ] Rates are scoped to companyGroupId and respect RLS
- [ ] `consolidatedRate` column is populated for all existing accounts via migration
- [ ] New accounts default `consolidatedRate` based on `incomeBalance` and `class`
- [ ] Seed data includes `consolidatedRate` for all accounts
- [ ] `translateTrialBalance` RPC correctly applies:
  - Closing rate to Balance Sheet accounts (`consolidatedRate = 'Current'`)
  - Average rate to Income Statement accounts (`consolidatedRate = 'Average'`)
  - Historical rate to Equity accounts (`consolidatedRate = 'Historical'`)
- [ ] CTA calculated correctly: translated total assets = translated total (liabilities + equity + CTA)
- [ ] CTA assigned to the `currencyTranslationAccount` from `accountDefault`
- [ ] Report pages show dual-currency columns when viewing a translated subsidiary
- [ ] Same-currency companies see no translation (rate = 1, no CTA)
- [ ] Missing exchange rates fall back gracefully (closing rate, then 1.0)
