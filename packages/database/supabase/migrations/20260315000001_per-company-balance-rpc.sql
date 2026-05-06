-- Per-company balance RPCs for financial reporting
-- Extends accountTreeBalances with optional company filtering

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
) LANGUAGE "plpgsql" SECURITY INVOKER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
    WITH RECURSIVE "accountTree" AS (
      SELECT
        a."id",
        a."id" AS "rootId",
        a."isGroup"
      FROM "account" a
      WHERE a."companyGroupId" = p_company_group_id AND a."active" = true

      UNION ALL

      SELECT
        child."id",
        t."rootId",
        child."isGroup"
      FROM "accountTree" t
      INNER JOIN "account" child ON child."parentId" = t."id"
      WHERE t."isGroup" = true
        AND child."companyGroupId" = p_company_group_id
        AND child."active" = true
    ),
    "leafBalances" AS (
      SELECT
        a."id" AS "accountId",
        COALESCE(SUM(jl."amount"), 0) AS "balance",
        COALESCE(SUM(CASE WHEN j."postingDate" <= to_date THEN jl."amount" ELSE 0 END), 0) AS "balanceAtDate",
        COALESCE(SUM(CASE WHEN j."postingDate" >= from_date AND j."postingDate" <= to_date THEN jl."amount" ELSE 0 END), 0) AS "netChange"
      FROM "account" a
      LEFT JOIN "journalLine" jl ON jl."accountId" = a."id"
        AND (p_company_id IS NULL OR jl."companyId" = p_company_id)
      LEFT JOIN "journal" j ON j."id" = jl."journalId"
      WHERE a."companyGroupId" = p_company_group_id
        AND a."isGroup" = false
        AND a."active" = true
      GROUP BY a."id"
    )
    SELECT
      t."rootId" AS "accountId",
      COALESCE(SUM(lb."balance"), 0)::NUMERIC(19, 4) AS "balance",
      COALESCE(SUM(lb."balanceAtDate"), 0)::NUMERIC(19, 4) AS "balanceAtDate",
      COALESCE(SUM(lb."netChange"), 0)::NUMERIC(19, 4) AS "netChange"
    FROM "accountTree" t
    LEFT JOIN "leafBalances" lb ON lb."accountId" = t."id" AND t."isGroup" = false
    GROUP BY t."rootId";
END;
$$;

-- Trial balance: flat list of leaf accounts with debit/credit split
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
  "accountClass" "glAccountClass",
  "incomeBalance" "glIncomeBalance",
  "debitBalance" NUMERIC(19, 4),
  "creditBalance" NUMERIC(19, 4),
  "netChange" NUMERIC(19, 4)
)
LANGUAGE "plpgsql" SECURITY INVOKER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    a."id" AS "accountId",
    a."number" AS "accountNumber",
    a."name" AS "accountName",
    a."class" AS "accountClass",
    a."incomeBalance",
    CASE
      WHEN a."class" IN ('Asset', 'Expense') AND b."balanceAtDate" > 0 THEN b."balanceAtDate"
      WHEN a."class" IN ('Liability', 'Equity', 'Revenue') AND b."balanceAtDate" < 0 THEN ABS(b."balanceAtDate")
      ELSE 0::NUMERIC(19, 4)
    END AS "debitBalance",
    CASE
      WHEN a."class" IN ('Liability', 'Equity', 'Revenue') AND b."balanceAtDate" >= 0 THEN b."balanceAtDate"
      WHEN a."class" IN ('Asset', 'Expense') AND b."balanceAtDate" < 0 THEN ABS(b."balanceAtDate")
      ELSE 0::NUMERIC(19, 4)
    END AS "creditBalance",
    b."netChange"
  FROM "account" a
  INNER JOIN "accountTreeBalancesByCompany"(p_company_group_id, p_company_id, from_date, to_date) b
    ON b."accountId" = a."id"
  WHERE a."isGroup" = false
    AND a."companyGroupId" = p_company_group_id
    AND a."active" = true
    AND (b."balanceAtDate" != 0 OR b."netChange" != 0)
  ORDER BY a."number";
END;
$$;
