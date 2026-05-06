-- Exchange rate history: daily spot rates auto-populated by sync job
-- Used by translateTrialBalance() to derive closing and average rates

CREATE TABLE "exchangeRateHistory" (
  "id" TEXT NOT NULL DEFAULT id('exr'),
  "currencyCode" TEXT NOT NULL,
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
    FOREIGN KEY ("currencyCode") REFERENCES "currencyCode"("code"),
  CONSTRAINT "exchangeRateHistory_rate_check" CHECK ("rate" > 0),
  CONSTRAINT "exchangeRateHistory_unique"
    UNIQUE ("currencyCode", "effectiveDate", "companyGroupId")
);

CREATE INDEX "exchangeRateHistory_lookup_idx"
  ON "exchangeRateHistory"("currencyCode", "companyGroupId", "effectiveDate" DESC);

ALTER TABLE "exchangeRateHistory" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "exchangeRateHistory_select" ON "exchangeRateHistory"
  FOR SELECT USING (
    "companyGroupId" = ANY (
      (SELECT "get_company_groups_for_employee"())::text[]
    )
  );

CREATE POLICY "exchangeRateHistory_insert" ON "exchangeRateHistory"
  FOR INSERT WITH CHECK (
    "companyGroupId" = ANY (
      (SELECT "get_company_groups_for_root_permission"('accounting_create'))::text[]
    )
  );

CREATE POLICY "exchangeRateHistory_update" ON "exchangeRateHistory"
  FOR UPDATE USING (
    "companyGroupId" = ANY (
      (SELECT "get_company_groups_for_root_permission"('accounting_update'))::text[]
    )
  );

CREATE POLICY "exchangeRateHistory_delete" ON "exchangeRateHistory"
  FOR DELETE USING (
    "companyGroupId" = ANY (
      (SELECT "get_company_groups_for_root_permission"('accounting_delete'))::text[]
    )
  );

-- Add historicalExchangeRate to currency for equity translation (IAS 21)
ALTER TABLE "currency" ADD COLUMN "historicalExchangeRate" NUMERIC(20, 8);

-- Populate consolidatedRate on existing accounts based on IAS 21 / ASC 830
UPDATE "account"
SET "consolidatedRate" = CASE
  WHEN "incomeBalance" = 'Income Statement' THEN 'Average'::"glConsolidatedRate"
  WHEN "class" = 'Equity' THEN 'Historical'::"glConsolidatedRate"
  ELSE 'Current'::"glConsolidatedRate"
END
WHERE "consolidatedRate" IS NULL;

ALTER TABLE "account" ALTER COLUMN "consolidatedRate" SET NOT NULL;
ALTER TABLE "account" ALTER COLUMN "consolidatedRate" SET DEFAULT 'Current'::"glConsolidatedRate";

-- Translation RPC: translate a company's trial balance to a target currency
-- Closing = latest rate on or before period end
-- Average = AVG(rate) over the period
-- Historical = currency.historicalExchangeRate (fallback to closing)
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
  "translatedBalance" NUMERIC(19, 4)
)
LANGUAGE "plpgsql" SECURITY INVOKER SET search_path = public
AS $$
DECLARE
  v_source_currency TEXT;
  v_closing_rate NUMERIC(20, 8);
  v_average_rate NUMERIC(20, 8);
  v_historical_rate NUMERIC(20, 8);
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
      b."balanceAtDate" AS "translatedBalance"
    FROM "accountTreeBalancesByCompany"(p_company_group_id, p_company_id, p_period_start, p_period_end) b
    INNER JOIN "account" a ON a."id" = b."accountId"
    WHERE a."isGroup" = false;
    RETURN;
  END IF;

  -- Closing rate: latest daily rate on or before period end
  SELECT "rate" INTO v_closing_rate
  FROM "exchangeRateHistory"
  WHERE "currencyCode" = v_source_currency
    AND "companyGroupId" = p_company_group_id
    AND "effectiveDate" <= p_period_end
  ORDER BY "effectiveDate" DESC LIMIT 1;

  -- Average rate: mean of daily rates over the period
  SELECT AVG("rate") INTO v_average_rate
  FROM "exchangeRateHistory"
  WHERE "currencyCode" = v_source_currency
    AND "companyGroupId" = p_company_group_id
    AND "effectiveDate" >= COALESCE(p_period_start, p_period_end - INTERVAL '1 year')
    AND "effectiveDate" <= p_period_end;

  -- Historical rate: from currency table (manually set for equity)
  SELECT "historicalExchangeRate" INTO v_historical_rate
  FROM "currency"
  WHERE "code" = v_source_currency
    AND "companyGroupId" = p_company_group_id;

  -- Defaults: average falls back to closing, historical falls back to closing, all fall back to 1
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
    END, 4) AS "translatedBalance"
  FROM "accountTreeBalancesByCompany"(p_company_group_id, p_company_id, p_period_start, p_period_end) b
  INNER JOIN "account" a ON a."id" = b."accountId"
  WHERE a."isGroup" = false;
END;
$$;

-- currencyTranslationAccount column and FK are added in 20260315000000_reset-chart-of-accounts.sql
