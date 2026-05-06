-- Journal Entries: add manual journal entry support to existing journal/journalLine tables

CREATE TYPE "journalEntrySourceType" AS ENUM (
  'Manual',
  'Purchase Receipt',
  'Purchase Invoice',
  'Purchase Return',
  'Sales Invoice',
  'Sales Shipment',
  'Sales Return',
  'Transfer Receipt',
  'Inventory Adjustment',
  'Production Order'
);

CREATE TYPE "journalEntryStatus" AS ENUM (
  'Draft',
  'Posted',
  'Reversed'
);

-- Delete existing journal lines and journals
DELETE FROM "journalLine";
DELETE FROM "journal";

-- Drop the journalEntries view if it exists (will be recreated below)
DROP VIEW IF EXISTS "journalEntries";

-- Change journal.id from SERIAL to TEXT with id('je') prefix
ALTER TABLE "journal" DROP CONSTRAINT "journal_pkey";
ALTER TABLE "journal" ALTER COLUMN "id" DROP DEFAULT;
ALTER TABLE "journal" ALTER COLUMN "id" TYPE TEXT;
ALTER TABLE "journal" ALTER COLUMN "id" SET DEFAULT id('je');
ALTER TABLE "journal" ADD CONSTRAINT "journal_pkey" PRIMARY KEY ("id");
DROP SEQUENCE IF EXISTS "journal_id_seq";

-- Change journalLine.journalId from INTEGER to TEXT
ALTER TABLE "journalLine" ALTER COLUMN "journalId" TYPE TEXT;

-- Add manual JE columns to journal
ALTER TABLE "journal" ADD COLUMN "journalEntryId" TEXT NOT NULL;
ALTER TABLE "journal" ADD COLUMN "status" "journalEntryStatus" NOT NULL DEFAULT 'Posted';
ALTER TABLE "journal" ADD COLUMN "sourceType" "journalEntrySourceType";
ALTER TABLE "journal" ADD COLUMN "reversalOfId" TEXT;
ALTER TABLE "journal" ADD COLUMN "reversedById" TEXT;
ALTER TABLE "journal" ADD COLUMN "postedAt" TIMESTAMP WITH TIME ZONE;
ALTER TABLE "journal" ADD COLUMN "postedBy" TEXT;
ALTER TABLE "journal" ADD COLUMN "createdBy" TEXT;
ALTER TABLE "journal" ADD COLUMN "updatedAt" TIMESTAMP WITH TIME ZONE;
ALTER TABLE "journal" ADD COLUMN "updatedBy" TEXT;

ALTER TABLE "journal" ADD CONSTRAINT "journal_reversalOfId_fkey"
  FOREIGN KEY ("reversalOfId") REFERENCES "journal"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "journal" ADD CONSTRAINT "journal_reversedById_fkey"
  FOREIGN KEY ("reversedById") REFERENCES "journal"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "journal" ADD CONSTRAINT "journal_createdBy_fkey"
  FOREIGN KEY ("createdBy") REFERENCES "user"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "journal" ADD CONSTRAINT "journal_postedBy_fkey"
  FOREIGN KEY ("postedBy") REFERENCES "user"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "journal" ADD CONSTRAINT "journal_updatedBy_fkey"
  FOREIGN KEY ("updatedBy") REFERENCES "user"("id") ON DELETE SET NULL ON UPDATE CASCADE;

CREATE UNIQUE INDEX "journal_journalEntryId_companyId_key"
  ON "journal" ("journalEntryId", "companyId");

CREATE INDEX "journal_status_idx" ON "journal" ("status", "companyId");

INSERT INTO "sequence" ("table", "name", "prefix", "suffix", "next", "size", "step", "companyId")
SELECT
  'journalEntry',
  'Journal Entry',
  'JE-%{yyyy}-%{mm}-',
  NULL,
  0,
  6,
  1,
  "id"
FROM "company"
ON CONFLICT DO NOTHING;



-- Allow UPDATE on Draft journals, or Posted journals (for reversal status change)
CREATE POLICY "UPDATE" ON "public"."journal"
  FOR UPDATE
  USING (
    "status" IN ('Draft', 'Posted')
    AND "companyId" = ANY (
      (SELECT get_companies_with_employee_permission('accounting_update'))::text[]
    )
  )
  WITH CHECK (true);

CREATE POLICY "DELETE" ON "public"."journal"
  FOR DELETE USING (
    "status" = 'Draft'
    AND "companyId" = ANY (
      (SELECT get_companies_with_employee_permission('accounting_delete'))::text[]
    )
  );

-- Add missing FK from journalLine to journal
ALTER TABLE "journalLine" ADD CONSTRAINT "journalLine_journalId_fkey"
  FOREIGN KEY ("journalId") REFERENCES "journal"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Add updatedAt/updatedBy to journalLine for draft editing
ALTER TABLE "journalLine" ADD COLUMN "updatedAt" TIMESTAMP WITH TIME ZONE;
ALTER TABLE "journalLine" ADD COLUMN "updatedBy" TEXT;
ALTER TABLE "journalLine" ADD CONSTRAINT "journalLine_updatedBy_fkey"
  FOREIGN KEY ("updatedBy") REFERENCES "user"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- Allow UPDATE and DELETE on journalLines belonging to Draft journals only
CREATE POLICY "UPDATE" ON "public"."journalLine"
  FOR UPDATE USING (
    "companyId" = ANY (
      (SELECT get_companies_with_employee_permission('accounting_update'))::text[]
    )
    AND EXISTS (
      SELECT 1 FROM "journal" j
      WHERE j."id" = "journalLine"."journalId" AND j."status" = 'Draft'
    )
  );

CREATE POLICY "DELETE" ON "public"."journalLine"
  FOR DELETE USING (
    "companyId" = ANY (
      (SELECT get_companies_with_employee_permission('accounting_delete'))::text[]
    )
    AND EXISTS (
      SELECT 1 FROM "journal" j
      WHERE j."id" = "journalLine"."journalId" AND j."status" = 'Draft'
    )
  );

-- View for manual journal entries list
CREATE OR REPLACE VIEW "journalEntries"
WITH (security_invoker = true)
AS
  SELECT
    j.*,
    COALESCE(SUM(
      CASE
        WHEN a."class" IN ('Asset', 'Expense') AND jl."amount" > 0 THEN jl."amount"
        WHEN a."class" IN ('Liability', 'Equity', 'Revenue') AND jl."amount" < 0 THEN ABS(jl."amount")
        ELSE 0
      END
    ), 0) AS "totalDebits",
    COALESCE(SUM(
      CASE
        WHEN a."class" IN ('Asset', 'Expense') AND jl."amount" < 0 THEN ABS(jl."amount")
        WHEN a."class" IN ('Liability', 'Equity', 'Revenue') AND jl."amount" > 0 THEN jl."amount"
        ELSE 0
      END
    ), 0) AS "totalCredits",
    COUNT(jl."id")::integer AS "lineCount"
  FROM "journal" j
  LEFT JOIN "journalLine" jl ON jl."journalId" = j."id"
  LEFT JOIN "account" a ON a."id" = jl."accountId"
  GROUP BY j."id";
