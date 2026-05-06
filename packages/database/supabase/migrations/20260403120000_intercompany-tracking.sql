-- Phase 3: Intercompany Elimination
-- Adds IC partner tracking to journal lines, IC transaction table,
-- auto-sync triggers for IC customers/suppliers, and matching/elimination RPCs.

-- 3a. Add IC partner tracking to journal lines
ALTER TABLE "journalLine" ADD COLUMN "intercompanyPartnerId" TEXT;

ALTER TABLE "journalLine" ADD CONSTRAINT "journalLine_intercompanyPartnerId_fkey"
  FOREIGN KEY ("intercompanyPartnerId") REFERENCES "company"("id") ON DELETE SET NULL;

CREATE INDEX "journalLine_intercompanyPartnerId_idx"
  ON "journalLine"("intercompanyPartnerId")
  WHERE "intercompanyPartnerId" IS NOT NULL;

COMMENT ON COLUMN "journalLine"."intercompanyPartnerId"
  IS 'The counterparty company within the same group for intercompany transactions';

-- 3e. Add intercompanyCompanyId to customer and supplier
ALTER TABLE "customer" ADD COLUMN "intercompanyCompanyId" TEXT;
ALTER TABLE "customer" ADD CONSTRAINT "customer_intercompanyCompanyId_fkey"
  FOREIGN KEY ("intercompanyCompanyId") REFERENCES "company"("id") ON DELETE SET NULL;
CREATE UNIQUE INDEX "customer_intercompanyCompanyId_companyId_idx"
  ON "customer"("intercompanyCompanyId", "companyId")
  WHERE "intercompanyCompanyId" IS NOT NULL;

ALTER TABLE "supplier" ADD COLUMN "intercompanyCompanyId" TEXT;
ALTER TABLE "supplier" ADD CONSTRAINT "supplier_intercompanyCompanyId_fkey"
  FOREIGN KEY ("intercompanyCompanyId") REFERENCES "company"("id") ON DELETE SET NULL;
CREATE UNIQUE INDEX "supplier_intercompanyCompanyId_companyId_idx"
  ON "supplier"("intercompanyCompanyId", "companyId")
  WHERE "intercompanyCompanyId" IS NOT NULL;

-- 3b. New table: intercompanyTransaction
CREATE TABLE "intercompanyTransaction" (
  "id" TEXT NOT NULL DEFAULT xid(),
  "companyGroupId" TEXT NOT NULL,
  "sourceCompanyId" TEXT NOT NULL,
  "targetCompanyId" TEXT NOT NULL,
  "sourceJournalLineId" TEXT NOT NULL,
  "targetJournalLineId" TEXT,
  "amount" NUMERIC(19, 4) NOT NULL,
  "currencyCode" TEXT NOT NULL,
  "description" TEXT,
  "documentType" "journalLineDocumentType",
  "documentId" TEXT,
  "status" TEXT NOT NULL DEFAULT 'Unmatched',
  "eliminationJournalId" TEXT,
  "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  "updatedAt" TIMESTAMP WITH TIME ZONE,

  CONSTRAINT "intercompanyTransaction_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "intercompanyTransaction_companyGroupId_fkey"
    FOREIGN KEY ("companyGroupId") REFERENCES "companyGroup"("id") ON DELETE CASCADE,
  CONSTRAINT "intercompanyTransaction_sourceCompanyId_fkey"
    FOREIGN KEY ("sourceCompanyId") REFERENCES "company"("id"),
  CONSTRAINT "intercompanyTransaction_targetCompanyId_fkey"
    FOREIGN KEY ("targetCompanyId") REFERENCES "company"("id"),
  CONSTRAINT "intercompanyTransaction_sourceJournalLineId_fkey"
    FOREIGN KEY ("sourceJournalLineId") REFERENCES "journalLine"("id"),
  CONSTRAINT "intercompanyTransaction_targetJournalLineId_fkey"
    FOREIGN KEY ("targetJournalLineId") REFERENCES "journalLine"("id"),
  CONSTRAINT "intercompanyTransaction_eliminationJournalId_fkey"
    FOREIGN KEY ("eliminationJournalId") REFERENCES "journal"("id"),
  CONSTRAINT "intercompanyTransaction_status_check"
    CHECK ("status" IN ('Unmatched', 'Matched', 'Eliminated'))
);

CREATE INDEX "intercompanyTransaction_companyGroupId_idx"
  ON "intercompanyTransaction"("companyGroupId");
CREATE INDEX "intercompanyTransaction_status_idx"
  ON "intercompanyTransaction"("status", "companyGroupId");
CREATE INDEX "intercompanyTransaction_source_target_idx"
  ON "intercompanyTransaction"("sourceCompanyId", "targetCompanyId");

-- Enable RLS
ALTER TABLE "intercompanyTransaction" ENABLE ROW LEVEL SECURITY;

-- RLS Policies for intercompanyTransaction
CREATE POLICY "intercompanyTransaction_select_policy" ON "intercompanyTransaction"
  FOR SELECT USING (
    "sourceCompanyId" = ANY(get_companies_with_employee_permission('accounting_create'))
    OR "targetCompanyId" = ANY(get_companies_with_employee_permission('accounting_create'))
  );

CREATE POLICY "intercompanyTransaction_insert_policy" ON "intercompanyTransaction"
  FOR INSERT WITH CHECK (
    "sourceCompanyId" = ANY(get_companies_with_employee_permission('accounting_create'))
    OR "targetCompanyId" = ANY(get_companies_with_employee_permission('accounting_create'))
  );

CREATE POLICY "intercompanyTransaction_update_policy" ON "intercompanyTransaction"
  FOR UPDATE USING (
    "sourceCompanyId" = ANY(get_companies_with_employee_permission('accounting_update'))
    OR "targetCompanyId" = ANY(get_companies_with_employee_permission('accounting_update'))
  );

CREATE POLICY "intercompanyTransaction_delete_policy" ON "intercompanyTransaction"
  FOR DELETE USING (
    "sourceCompanyId" = ANY(get_companies_with_employee_permission('accounting_delete'))
    OR "targetCompanyId" = ANY(get_companies_with_employee_permission('accounting_delete'))
  );

-- 3f. Trigger: Auto-create IC customers/suppliers when a company joins a group
CREATE OR REPLACE FUNCTION "sync_intercompany_partners"()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_sibling RECORD;
  v_group_id TEXT;
BEGIN
  v_group_id := NEW."companyGroupId";

  -- Skip elimination entities
  IF NEW."isEliminationEntity" = true THEN
    RETURN NEW;
  END IF;

  -- Skip if no group
  IF v_group_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- For each sibling (non-elimination) company in the group
  FOR v_sibling IN
    SELECT c."id", c."name"
    FROM "company" c
    WHERE c."companyGroupId" = v_group_id
      AND c."id" != NEW."id"
      AND c."isEliminationEntity" = false
      AND c."active" = true
  LOOP
    -- Create customer in sibling for this company
    INSERT INTO "customer" ("name", "companyId", "intercompanyCompanyId")
    VALUES (NEW."name", v_sibling."id", NEW."id")
    ON CONFLICT DO NOTHING;

    -- Create supplier in sibling for this company
    INSERT INTO "supplier" ("name", "companyId", "intercompanyCompanyId")
    VALUES (NEW."name", v_sibling."id", NEW."id")
    ON CONFLICT DO NOTHING;

    -- Create customer in this company for the sibling
    INSERT INTO "customer" ("name", "companyId", "intercompanyCompanyId")
    VALUES (v_sibling."name", NEW."id", v_sibling."id")
    ON CONFLICT DO NOTHING;

    -- Create supplier in this company for the sibling
    INSERT INTO "supplier" ("name", "companyId", "intercompanyCompanyId")
    VALUES (v_sibling."name", NEW."id", v_sibling."id")
    ON CONFLICT DO NOTHING;
  END LOOP;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "company_sync_ic_partners"
  AFTER INSERT OR UPDATE OF "companyGroupId" ON "company"
  FOR EACH ROW
  EXECUTE FUNCTION "sync_intercompany_partners"();

-- 3g. Trigger: Sync name/details on company update
CREATE OR REPLACE FUNCTION "sync_intercompany_partner_details"()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF NEW."name" IS DISTINCT FROM OLD."name" THEN
    UPDATE "customer"
    SET "name" = NEW."name"
    WHERE "intercompanyCompanyId" = NEW."id";

    UPDATE "supplier"
    SET "name" = NEW."name"
    WHERE "intercompanyCompanyId" = NEW."id";
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "company_sync_ic_partner_details"
  AFTER UPDATE OF "name" ON "company"
  FOR EACH ROW
  EXECUTE FUNCTION "sync_intercompany_partner_details"();

-- 3h. Trigger: Clean up on company removal from group
CREATE OR REPLACE FUNCTION "cleanup_intercompany_partners"()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  -- Clear the IC link on sibling records. This bypasses the prevent_ic_record_deletion
  -- trigger (which blocks deletion of records that still have intercompanyCompanyId set).
  -- The FK ON DELETE SET NULL on intercompanyCompanyId handles the rest.
  IF TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND NEW."companyGroupId" IS DISTINCT FROM OLD."companyGroupId") THEN
    UPDATE "customer" SET "intercompanyCompanyId" = NULL WHERE "intercompanyCompanyId" = OLD."id";
    UPDATE "supplier" SET "intercompanyCompanyId" = NULL WHERE "intercompanyCompanyId" = OLD."id";
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER "company_cleanup_ic_partners"
  AFTER DELETE OR UPDATE OF "companyGroupId" ON "company"
  FOR EACH ROW
  EXECUTE FUNCTION "cleanup_intercompany_partners"();

-- 3i. Trigger: Prevent deletion of IC customers/suppliers
CREATE OR REPLACE FUNCTION "prevent_ic_record_deletion"()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  IF OLD."intercompanyCompanyId" IS NOT NULL THEN
    RAISE EXCEPTION 'Cannot delete intercompany % record. Remove the subsidiary from the group first.', TG_TABLE_NAME;
  END IF;
  RETURN OLD;
END;
$$;

CREATE TRIGGER "customer_prevent_ic_deletion"
  BEFORE DELETE ON "customer"
  FOR EACH ROW
  EXECUTE FUNCTION "prevent_ic_record_deletion"();

CREATE TRIGGER "supplier_prevent_ic_deletion"
  BEFORE DELETE ON "supplier"
  FOR EACH ROW
  EXECUTE FUNCTION "prevent_ic_record_deletion"();

-- 3c. RPC: matchIntercompanyTransactions
CREATE OR REPLACE FUNCTION "matchIntercompanyTransactions" (
  p_company_group_id TEXT
)
RETURNS TABLE (
  "id" TEXT,
  "sourceCompanyId" TEXT,
  "targetCompanyId" TEXT,
  "amount" NUMERIC(19, 4),
  "status" TEXT,
  "matchedWithId" TEXT
)
LANGUAGE "plpgsql"
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  -- Check that user belongs to at least one company in this group
  IF NOT EXISTS (
    SELECT 1
    FROM "userToCompany" utc
    INNER JOIN "company" c ON c."id" = utc."companyId"
    WHERE utc."userId" = auth.uid()::text
      AND utc."role" = 'employee'
      AND c."companyGroupId" = p_company_group_id
  ) THEN
    RAISE EXCEPTION 'Insufficient permissions to match intercompany transactions';
  END IF;

  -- Match unmatched IC transactions:
  -- Source's receivable against target's payable for the same amount and partner
  WITH matches AS (
    SELECT
      src."id" AS "sourceId",
      tgt."id" AS "targetId"
    FROM "intercompanyTransaction" src
    INNER JOIN "intercompanyTransaction" tgt
      ON src."sourceCompanyId" = tgt."targetCompanyId"
      AND src."targetCompanyId" = tgt."sourceCompanyId"
      AND src."amount" = tgt."amount"
      AND src."companyGroupId" = tgt."companyGroupId"
    WHERE src."companyGroupId" = p_company_group_id
      AND src."status" = 'Unmatched'
      AND tgt."status" = 'Unmatched'
      AND src."sourceJournalLineId" < tgt."sourceJournalLineId"
  )
  UPDATE "intercompanyTransaction" ict
  SET
    "status" = 'Matched',
    "targetJournalLineId" = CASE
      WHEN ict."id" = m."sourceId" THEN (SELECT t."sourceJournalLineId" FROM "intercompanyTransaction" t WHERE t."id" = m."targetId")
      ELSE (SELECT t."sourceJournalLineId" FROM "intercompanyTransaction" t WHERE t."id" = m."sourceId")
    END,
    "updatedAt" = NOW()
  FROM matches m
  WHERE ict."id" IN (m."sourceId", m."targetId");

  -- Return current state
  RETURN QUERY
  SELECT
    ict."id",
    ict."sourceCompanyId",
    ict."targetCompanyId",
    ict."amount",
    ict."status",
    ict."targetJournalLineId" AS "matchedWithId"
  FROM "intercompanyTransaction" ict
  WHERE ict."companyGroupId" = p_company_group_id
  ORDER BY ict."createdAt" DESC;
END;
$$;

-- Helper: Find the lowest common ancestor (parent) of two companies
-- Walks up the parentCompanyId chain for each company and returns the first shared ancestor.
CREATE OR REPLACE FUNCTION "findLowestCommonParent" (
  p_company_a TEXT,
  p_company_b TEXT
)
RETURNS TEXT
LANGUAGE "plpgsql"
STABLE
SET search_path = public
AS $$
DECLARE
  v_result TEXT;
BEGIN
  -- Build ancestor chains for both companies, then find the lowest shared one.
  -- "Lowest" = the ancestor that appears first when walking up from a child.
  WITH RECURSIVE
    ancestors_a AS (
      SELECT "id", "parentCompanyId", 0 AS depth
      FROM "company" WHERE "id" = p_company_a
      UNION ALL
      SELECT c."id", c."parentCompanyId", a.depth + 1
      FROM "company" c
      INNER JOIN ancestors_a a ON a."parentCompanyId" = c."id"
    ),
    ancestors_b AS (
      SELECT "id", "parentCompanyId", 0 AS depth
      FROM "company" WHERE "id" = p_company_b
      UNION ALL
      SELECT c."id", c."parentCompanyId", b.depth + 1
      FROM "company" c
      INNER JOIN ancestors_b b ON b."parentCompanyId" = c."id"
    )
  SELECT a."id" INTO v_result
  FROM ancestors_a a
  INNER JOIN ancestors_b b ON a."id" = b."id"
  WHERE a."id" != p_company_a  -- exclude the companies themselves
    AND a."id" != p_company_b
  ORDER BY (a.depth + b.depth) ASC  -- lowest = smallest combined distance
  LIMIT 1;

  -- If no common parent found (e.g., direct parent-child), check if one is an ancestor of the other
  IF v_result IS NULL THEN
    -- Check if A is an ancestor of B
    SELECT a."id" INTO v_result
    FROM (
      WITH RECURSIVE anc AS (
        SELECT "id", "parentCompanyId" FROM "company" WHERE "id" = p_company_b
        UNION ALL
        SELECT c."id", c."parentCompanyId"
        FROM "company" c INNER JOIN anc ON anc."parentCompanyId" = c."id"
      )
      SELECT "id" FROM anc WHERE "id" = p_company_a
    ) a;

    -- If A is an ancestor of B, the LCA is A
    IF v_result IS NOT NULL THEN
      RETURN v_result;
    END IF;

    -- Check if B is an ancestor of A
    SELECT a."id" INTO v_result
    FROM (
      WITH RECURSIVE anc AS (
        SELECT "id", "parentCompanyId" FROM "company" WHERE "id" = p_company_a
        UNION ALL
        SELECT c."id", c."parentCompanyId"
        FROM "company" c INNER JOIN anc ON anc."parentCompanyId" = c."id"
      )
      SELECT "id" FROM anc WHERE "id" = p_company_b
    ) a;

    IF v_result IS NOT NULL THEN
      RETURN v_result;
    END IF;
  END IF;

  RETURN v_result;
END;
$$;

-- 3d. RPC: generateEliminationEntries
-- Uses the "lowest common parent" rule: elimination entries are posted to the
-- elimination entity belonging to the lowest common parent of the two transacting companies.
-- This supports multi-tier hierarchies (parent-child, sibling, cousin/cross-branch).
CREATE OR REPLACE FUNCTION "generateEliminationEntries" (
  p_company_group_id TEXT,
  p_user_id TEXT
)
RETURNS INTEGER  -- returns count of journals created
LANGUAGE "plpgsql"
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_rec RECORD;
  v_lca_id TEXT;
  v_elim_id TEXT;
  v_journal_id INTEGER;
  v_period_id TEXT;
  v_journals_created INTEGER := 0;
  v_journals_by_elim RECORD;
BEGIN
  -- Check that user belongs to at least one company in this group
  IF NOT EXISTS (
    SELECT 1
    FROM "userToCompany" utc
    INNER JOIN "company" c ON c."id" = utc."companyId"
    WHERE utc."userId" = auth.uid()::text
      AND utc."role" = 'employee'
      AND c."companyGroupId" = p_company_group_id
  ) THEN
    RAISE EXCEPTION 'Insufficient permissions to generate elimination entries';
  END IF;

  -- Process each matched IC transaction pair, routing to the correct elimination entity
  -- Group matched transactions by their lowest common parent's elimination entity
  FOR v_rec IN
    SELECT DISTINCT
      ict."sourceCompanyId",
      ict."targetCompanyId"
    FROM "intercompanyTransaction" ict
    WHERE ict."companyGroupId" = p_company_group_id
      AND ict."status" = 'Matched'
  LOOP
    -- Find the lowest common parent
    v_lca_id := "findLowestCommonParent"(v_rec."sourceCompanyId", v_rec."targetCompanyId");

    -- Find the elimination entity for this LCA
    SELECT c."id" INTO v_elim_id
    FROM "company" c
    WHERE c."parentCompanyId" = v_lca_id
      AND c."isEliminationEntity" = true
      AND c."companyGroupId" = p_company_group_id
    LIMIT 1;

    -- If no elimination entity at the LCA level, fall back to any in the group
    IF v_elim_id IS NULL THEN
      SELECT c."id" INTO v_elim_id
      FROM "company" c
      WHERE c."companyGroupId" = p_company_group_id
        AND c."isEliminationEntity" = true
      LIMIT 1;
    END IF;

    IF v_elim_id IS NULL THEN
      RAISE EXCEPTION 'No elimination entity found for company group %', p_company_group_id;
    END IF;

    -- Get active accounting period for elimination entity
    SELECT "id" INTO v_period_id
    FROM "accountingPeriod"
    WHERE "companyId" = v_elim_id
      AND "status" = 'Active'
    LIMIT 1;

    -- Create elimination journal on this elimination entity
    INSERT INTO "journal" ("description", "accountingPeriodId", "companyId", "postingDate")
    VALUES (
      'IC Elimination: ' || v_rec."sourceCompanyId" || ' ↔ ' || v_rec."targetCompanyId",
      v_period_id,
      v_elim_id,
      CURRENT_DATE
    )
    RETURNING "id" INTO v_journal_id;

    v_journals_created := v_journals_created + 1;

    -- Generate reversing entries from source journal lines
    INSERT INTO "journalLine" (
      "journalId", "accountId", "description", "amount",
      "documentType", "journalLineReference",
      "companyId", "companyGroupId"
    )
    SELECT
      v_journal_id,
      jl."accountId",
      'IC Elimination: ' || COALESCE(jl."description", ''),
      -jl."amount",
      jl."documentType",
      'ic-elim-' || ict."id",
      v_elim_id,
      p_company_group_id
    FROM "intercompanyTransaction" ict
    INNER JOIN "journalLine" jl ON jl."id" = ict."sourceJournalLineId"
    WHERE ict."companyGroupId" = p_company_group_id
      AND ict."status" = 'Matched'
      AND ict."sourceCompanyId" = v_rec."sourceCompanyId"
      AND ict."targetCompanyId" = v_rec."targetCompanyId";

    -- Also reverse the matched counterpart entries
    INSERT INTO "journalLine" (
      "journalId", "accountId", "description", "amount",
      "documentType", "journalLineReference",
      "companyId", "companyGroupId"
    )
    SELECT
      v_journal_id,
      jl."accountId",
      'IC Elimination: ' || COALESCE(jl."description", ''),
      -jl."amount",
      jl."documentType",
      'ic-elim-' || ict."id",
      v_elim_id,
      p_company_group_id
    FROM "intercompanyTransaction" ict
    INNER JOIN "journalLine" jl ON jl."id" = ict."targetJournalLineId"
    WHERE ict."companyGroupId" = p_company_group_id
      AND ict."status" = 'Matched'
      AND ict."sourceCompanyId" = v_rec."sourceCompanyId"
      AND ict."targetCompanyId" = v_rec."targetCompanyId"
      AND ict."targetJournalLineId" IS NOT NULL;

    -- Update these IC transactions to Eliminated
    UPDATE "intercompanyTransaction"
    SET "status" = 'Eliminated',
        "eliminationJournalId" = v_journal_id,
        "updatedAt" = NOW()
    WHERE "companyGroupId" = p_company_group_id
      AND "status" = 'Matched'
      AND "sourceCompanyId" = v_rec."sourceCompanyId"
      AND "targetCompanyId" = v_rec."targetCompanyId";

  END LOOP;

  RETURN v_journals_created;
END;
$$;

-- RPC: getIntercompanyBalance
-- Returns a matrix of IC balances between companies in a group
CREATE OR REPLACE FUNCTION "getIntercompanyBalance" (
  p_company_group_id TEXT
)
RETURNS TABLE (
  "sourceCompanyId" TEXT,
  "sourceCompanyName" TEXT,
  "targetCompanyId" TEXT,
  "targetCompanyName" TEXT,
  "balance" NUMERIC(19, 4)
)
LANGUAGE "plpgsql"
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  -- Check that user belongs to at least one company in this group
  IF NOT EXISTS (
    SELECT 1
    FROM "userToCompany" utc
    INNER JOIN "company" c ON c."id" = utc."companyId"
    WHERE utc."userId" = auth.uid()::text
      AND utc."role" = 'employee'
      AND c."companyGroupId" = p_company_group_id
  ) THEN
    RAISE EXCEPTION 'Insufficient permissions to view intercompany balance';
  END IF;

  RETURN QUERY
  SELECT
    ict."sourceCompanyId",
    sc."name" AS "sourceCompanyName",
    ict."targetCompanyId",
    tc."name" AS "targetCompanyName",
    SUM(
      CASE
        WHEN ict."status" != 'Eliminated' THEN ict."amount"
        ELSE 0
      END
    ) AS "balance"
  FROM "intercompanyTransaction" ict
  INNER JOIN "company" sc ON sc."id" = ict."sourceCompanyId"
  INNER JOIN "company" tc ON tc."id" = ict."targetCompanyId"
  WHERE ict."companyGroupId" = p_company_group_id
  GROUP BY ict."sourceCompanyId", sc."name", ict."targetCompanyId", tc."name"
  HAVING SUM(
    CASE
      WHEN ict."status" != 'Eliminated' THEN ict."amount"
      ELSE 0
    END
  ) != 0;
END;
$$;
