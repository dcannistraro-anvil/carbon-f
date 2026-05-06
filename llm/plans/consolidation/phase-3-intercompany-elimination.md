# Phase 3: Intercompany Elimination

## Goal

Identify, match, and eliminate intercompany transactions so that consolidated financials do not double-count internal activity. When Company A sells to Company B within the same group, the sale revenue, purchase expense, receivable, and payable must all be removed from the consolidated view.

This phase introduces IC transaction tagging at posting time, a matching engine, and automated elimination journal entry generation on the elimination entity.

**Standalone value:** Even before full consolidation, IC reconciliation reports are critical for multi-entity groups to ensure their intercompany accounts balance.

## Dependencies

- Phase 1 must be complete (per-company balance querying)
- The elimination entity company must exist (auto-created when first subsidiary is added — this logic already works in `seed-company/index.ts`)

## How IC Transactions Flow

```
Company A sells to Company B (both in same companyGroup)

                  Company A (Seller)                    Company B (Buyer)
                  ─────────────────                     ─────────────────
post-sales-invoice:                      post-purchase-invoice:
  DR 1130 IC Receivables  $100             DR 5020 Purchases        $100
  CR 4010 Sales           $100             CR 2020 IC Payables      $100

  journalLine.intercompanyPartnerId        journalLine.intercompanyPartnerId
    = companyB.id                            = companyA.id

                         Elimination Entity
                         ──────────────────
  generateEliminationEntries:
    DR 4010 Sales           $100    (eliminate A's revenue)
    CR 5020 Purchases       $100    (eliminate B's cost)
    DR 2020 IC Payables     $100    (eliminate B's payable)
    CR 1130 IC Receivables  $100    (eliminate A's receivable)
```

After consolidation: IC revenue, IC cost, IC receivable, and IC payable all net to zero.

## Database Changes

### 3a. Add IC Partner Tracking to Journal Lines

```sql
ALTER TABLE "journalLine" ADD COLUMN "intercompanyPartnerId" TEXT;

ALTER TABLE "journalLine" ADD CONSTRAINT "journalLine_intercompanyPartnerId_fkey"
  FOREIGN KEY ("intercompanyPartnerId") REFERENCES "company"("id") ON DELETE SET NULL;

CREATE INDEX "journalLine_intercompanyPartnerId_idx"
  ON "journalLine"("intercompanyPartnerId")
  WHERE "intercompanyPartnerId" IS NOT NULL;

COMMENT ON COLUMN "journalLine"."intercompanyPartnerId"
  IS 'The counterparty company within the same group for intercompany transactions';
```

### 3b. New Table: `intercompanyTransaction`

Tracks IC transaction pairs and their matching/elimination status.

```sql
CREATE TABLE "intercompanyTransaction" (
  "id" TEXT NOT NULL DEFAULT id('ict'),
  "companyGroupId" TEXT NOT NULL,
  "sourceCompanyId" TEXT NOT NULL,
  "targetCompanyId" TEXT NOT NULL,
  "sourceJournalLineId" TEXT NOT NULL,
  "targetJournalLineId" TEXT,
  "amount" NUMERIC(19, 4) NOT NULL,
  "currencyCode" TEXT NOT NULL,
  "documentType" "journalLineDocumentType",
  "documentId" TEXT,
  "status" TEXT NOT NULL DEFAULT 'Unmatched',
  "eliminationJournalId" INTEGER,
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

ALTER TABLE "intercompanyTransaction" ENABLE ROW LEVEL SECURITY;
```

**RLS:**

```sql
CREATE POLICY "intercompanyTransaction_select" ON "intercompanyTransaction"
  FOR SELECT USING (
    "companyGroupId" = ANY (SELECT "get_company_groups_for_employee"())
  );

CREATE POLICY "intercompanyTransaction_insert" ON "intercompanyTransaction"
  FOR INSERT WITH CHECK (
    "companyGroupId" = ANY (SELECT "get_company_groups_for_root_permission"('accounting_create'))
  );

CREATE POLICY "intercompanyTransaction_update" ON "intercompanyTransaction"
  FOR UPDATE USING (
    "companyGroupId" = ANY (SELECT "get_company_groups_for_root_permission"('accounting_update'))
  );
```

### 3c. New RPC: `matchIntercompanyTransactions`

```sql
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
      AND src."sourceJournalLineId" < tgt."sourceJournalLineId"  -- prevent double-matching
  )
  UPDATE "intercompanyTransaction" ict
  SET
    "status" = 'Matched',
    "targetJournalLineId" = CASE
      WHEN ict."id" = m."sourceId" THEN (SELECT "sourceJournalLineId" FROM "intercompanyTransaction" WHERE "id" = m."targetId")
      ELSE (SELECT "sourceJournalLineId" FROM "intercompanyTransaction" WHERE "id" = m."sourceId")
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
```

### 3d. Helper: `findLowestCommonParent`

Walks up the `parentCompanyId` chain for two companies and returns the first shared ancestor. Used by `generateEliminationEntries` to route eliminations to the correct elimination entity per the **lowest common parent rule**:

- **Parent ↔ Child:** eliminations post to the parent's elimination entity
- **Siblings (same parent):** eliminations post to the shared parent's elimination entity
- **Cousins (cross-branch):** eliminations post to the lowest shared ancestor's elimination entity

Each parent that has subsidiaries gets its own elimination entity (auto-created by `seed-company`, named "Elimination - [ParentName]"). This enables correct sub-consolidations at each level of the hierarchy.

### 3e. New RPC: `generateEliminationEntries`

```sql
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
  v_elimination_company_id TEXT;
  v_journal_id INTEGER;
  v_period_id TEXT;
BEGIN
  -- Find the elimination entity
  SELECT c."id" INTO v_elimination_company_id
  FROM "company" c
  WHERE c."companyGroupId" = p_company_group_id
    AND c."isEliminationEntity" = true
  LIMIT 1;

  IF v_elimination_company_id IS NULL THEN
    RAISE EXCEPTION 'No elimination entity found for company group %', p_company_group_id;
  END IF;

  -- Get active accounting period for elimination entity
  SELECT "id" INTO v_period_id
  FROM "accountingPeriod"
  WHERE "companyId" = v_elimination_company_id
    AND "status" = 'Active'
  LIMIT 1;

  -- Create elimination journal
  INSERT INTO "journal" ("description", "accountingPeriodId", "companyId", "postingDate")
  VALUES ('Intercompany Elimination Entries', v_period_id, v_elimination_company_id, CURRENT_DATE)
  RETURNING "id" INTO v_journal_id;

  -- For each matched IC transaction, generate reversing entries
  INSERT INTO "journalLine" (
    "journalId", "accountNumber", "description", "amount",
    "documentType", "journalLineReference",
    "companyId", "companyGroupId"
  )
  SELECT
    v_journal_id,
    jl."accountNumber",
    'IC Elimination: ' || jl."description",
    -jl."amount",  -- reverse the original entry
    jl."documentType",
    'ic-elim-' || ict."id",
    v_elimination_company_id,
    p_company_group_id
  FROM "intercompanyTransaction" ict
  INNER JOIN "journalLine" jl ON jl."id" = ict."sourceJournalLineId"
  WHERE ict."companyGroupId" = p_company_group_id
    AND ict."status" = 'Matched';

  -- Also reverse the matched counterpart entries
  INSERT INTO "journalLine" (
    "journalId", "accountNumber", "description", "amount",
    "documentType", "journalLineReference",
    "companyId", "companyGroupId"
  )
  SELECT
    v_journal_id,
    jl."accountNumber",
    'IC Elimination: ' || jl."description",
    -jl."amount",
    jl."documentType",
    'ic-elim-' || ict."id",
    v_elimination_company_id,
    p_company_group_id
  FROM "intercompanyTransaction" ict
  INNER JOIN "journalLine" jl ON jl."id" = ict."targetJournalLineId"
  WHERE ict."companyGroupId" = p_company_group_id
    AND ict."status" = 'Matched'
    AND ict."targetJournalLineId" IS NOT NULL;

  -- Update IC transactions to Eliminated
  UPDATE "intercompanyTransaction"
  SET "status" = 'Eliminated',
      "eliminationJournalId" = v_journal_id,
      "updatedAt" = NOW()
  WHERE "companyGroupId" = p_company_group_id
    AND "status" = 'Matched';

  RETURN v_journal_id;
END;
$$;
```

### 3e. Add `intercompanyCompanyId` to `customer` and `supplier`

Links a customer/supplier record to a sibling company within the same group. When set, the posting functions know the transaction is intercompany.

```sql
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
```

The unique index ensures at most one IC customer/supplier per sibling pair per company.

### 3f. Trigger: Auto-create IC customers/suppliers when a company joins a group

When a company is inserted or its `companyGroupId` is updated, automatically create cross-company customer and supplier records for all siblings.

```sql
CREATE OR REPLACE FUNCTION "sync_intercompany_partners"()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
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
    SELECT c."id", c."name", c."taxId", c."baseCurrencyCode"
    FROM "company" c
    WHERE c."companyGroupId" = v_group_id
      AND c."id" != NEW."id"
      AND c."isEliminationEntity" = false
      AND c."active" = true
  LOOP
    -- Create customer in sibling for this company
    INSERT INTO "customer" ("name", "companyId", "taxId", "intercompanyCompanyId")
    VALUES (NEW."name", v_sibling."id", NEW."taxId", NEW."id")
    ON CONFLICT DO NOTHING;

    -- Create supplier in sibling for this company
    INSERT INTO "supplier" ("name", "companyId", "taxId", "intercompanyCompanyId")
    VALUES (NEW."name", v_sibling."id", NEW."taxId", NEW."id")
    ON CONFLICT DO NOTHING;

    -- Create customer in this company for the sibling
    INSERT INTO "customer" ("name", "companyId", "taxId", "intercompanyCompanyId")
    VALUES (v_sibling."name", NEW."id", v_sibling."taxId", v_sibling."id")
    ON CONFLICT DO NOTHING;

    -- Create supplier in this company for the sibling
    INSERT INTO "supplier" ("name", "companyId", "taxId", "intercompanyCompanyId")
    VALUES (v_sibling."name", NEW."id", v_sibling."taxId", v_sibling."id")
    ON CONFLICT DO NOTHING;
  END LOOP;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "company_sync_ic_partners"
  AFTER INSERT OR UPDATE OF "companyGroupId" ON "company"
  FOR EACH ROW
  EXECUTE FUNCTION "sync_intercompany_partners"();
```

### 3g. Trigger: Sync name/details on company update

```sql
CREATE OR REPLACE FUNCTION "sync_intercompany_partner_details"()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW."name" IS DISTINCT FROM OLD."name" OR NEW."taxId" IS DISTINCT FROM OLD."taxId" THEN
    UPDATE "customer"
    SET "name" = NEW."name", "taxId" = NEW."taxId"
    WHERE "intercompanyCompanyId" = NEW."id";

    UPDATE "supplier"
    SET "name" = NEW."name", "taxId" = NEW."taxId"
    WHERE "intercompanyCompanyId" = NEW."id";
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "company_sync_ic_partner_details"
  AFTER UPDATE OF "name", "taxId" ON "company"
  FOR EACH ROW
  EXECUTE FUNCTION "sync_intercompany_partner_details"();
```

### 3h. Trigger: Clean up on company removal from group

```sql
CREATE OR REPLACE FUNCTION "cleanup_intercompany_partners"()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- On delete or removal from group, remove IC records pointing to this company
  IF TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND NEW."companyGroupId" IS DISTINCT FROM OLD."companyGroupId") THEN
    DELETE FROM "customer" WHERE "intercompanyCompanyId" = OLD."id";
    DELETE FROM "supplier" WHERE "intercompanyCompanyId" = OLD."id";
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
```

### 3i. Trigger: Prevent deletion of IC customers/suppliers

```sql
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
```

### Migration

Single migration file: `YYYYMMDDHHMMSS_intercompany-tracking.sql`

Contains: `journalLine.intercompanyPartnerId` column, `customer.intercompanyCompanyId` and `supplier.intercompanyCompanyId` columns, IC partner sync/cleanup/deletion triggers, `intercompanyTransaction` table with RLS, both RPCs.

## Edge Function Modifications

### Detecting Intercompany Transactions

Detection is trivial because IC customer/supplier records are auto-created with `intercompanyCompanyId` set by the database trigger when subsidiaries join a group.

### Modify `post-sales-invoice` (`packages/database/supabase/functions/post-sales-invoice/index.ts`)

When the customer has `intercompanyCompanyId` set:

1. Use account **1130** (IC Receivables) instead of **1110** (Accounts Receivable) for the AR entry
2. Set `intercompanyPartnerId` on the IC journal lines
3. Insert a row in `intercompanyTransaction` with `status = 'Unmatched'`

```typescript
// Detect IC transaction — just a null check
const isIntercompany = customer.intercompanyCompanyId != null;

if (isIntercompany) {
  // Use IC Receivables instead of regular AR
  journalLineInserts.push({
    accountNumber: "1130",  // IC Receivables
    intercompanyPartnerId: customer.intercompanyCompanyId,
    // ... rest of journal line
  });

  // Create IC transaction record
  await trx.insertInto("intercompanyTransaction").values({
    companyGroupId,
    sourceCompanyId: companyId,
    targetCompanyId: customer.intercompanyCompanyId,
    sourceJournalLineId: journalLineId,
    amount: invoiceTotal,
    currencyCode: invoice.currencyCode,
    documentType: "Invoice",
    documentId: invoice.id,
    status: "Unmatched",
  }).execute();
}
```

### Modify `post-purchase-invoice` (`packages/database/supabase/functions/post-purchase-invoice/index.ts`)

Mirror of the sales side:

1. Use account **2020** (IC Payables) instead of default AP for the payable entry
2. Set `intercompanyPartnerId` on the IC journal lines
3. Insert a row in `intercompanyTransaction` with `status = 'Unmatched'`

## Backend / Service Layer

### Add to `apps/erp/app/modules/accounting/accounting.service.ts`

```typescript
export async function getIntercompanyTransactions(
  client: SupabaseClient<Database>,
  companyGroupId: string,
  args: { status?: string }
)

export async function createIntercompanyTransaction(
  client: SupabaseClient<Database>,
  input: {
    companyGroupId: string;
    sourceCompanyId: string;
    targetCompanyId: string;
    amount: number;
    currencyCode: string;
    description: string;
    debitAccountNumber: string;  // e.g. 1130 IC Receivables
    creditAccountNumber: string; // e.g. 6010 IC Management Fee Expense
    userId: string;
  }
)
// Creates a journal + journal lines on the source company,
// inserts an intercompanyTransaction with status 'Unmatched',
// and sets intercompanyPartnerId on the journal lines.

export async function runIntercompanyMatching(
  client: SupabaseClient<Database>,
  companyGroupId: string
)

export async function generateEliminations(
  client: SupabaseClient<Database>,
  companyGroupId: string,
  userId: string
)

export async function getEliminationJournal(
  client: SupabaseClient<Database>,
  companyGroupId: string,
  journalId: number
)

export async function getIntercompanyBalance(
  client: SupabaseClient<Database>,
  companyGroupId: string
)
// Returns a matrix of IC balances: company A owes company B $X
```

## UI

### New Routes

| Route file | URL path | Purpose |
|---|---|---|
| `routes/x+/accounting+/intercompany.tsx` | `/x/accounting/intercompany` | IC transaction list with status + balance matrix |
| `routes/x+/accounting+/intercompany.new.tsx` | `/x/accounting/intercompany/new` | Create a generic IC transaction (not tied to invoice) |
| `routes/x+/accounting+/intercompany.match.tsx` | (action route) | Trigger matching |
| `routes/x+/accounting+/intercompany.eliminate.tsx` | (action route) | Generate elimination entries |

### Sidebar

Add under "Manage" group:

```typescript
{ name: "Intercompany", to: path.to.intercompany }
```

### New Components

| Component | Location | Purpose |
|---|---|---|
| `IntercompanyTransactionTable` | `modules/accounting/ui/Intercompany/IntercompanyTransactionTable.tsx` | Table with status badges (Unmatched/Matched/Eliminated) |
| `IntercompanyTransactionForm` | `modules/accounting/ui/Intercompany/IntercompanyTransactionForm.tsx` | Form for creating generic IC transactions |
| `IntercompanyBalanceMatrix` | `modules/accounting/ui/Intercompany/IntercompanyBalanceMatrix.tsx` | Grid showing who owes whom |
| `IntercompanyMatchingSummary` | `modules/accounting/ui/Intercompany/IntercompanyMatchingSummary.tsx` | Summary stats: X matched, Y unmatched, Z eliminated |

### Generic IC Transaction Form (`intercompany.new.tsx`)

For intercompany charges that don't originate from a sales or purchase invoice — e.g., management fees, shared service allocations, intercompany loans, cost recharges.

**Form fields:**

| Field | Type | Required | Description |
|---|---|---|---|
| Source Company | Select (siblings in group) | Yes | The company recording the charge |
| Target Company | Select (siblings in group) | Yes | The counterparty company |
| Amount | Number | Yes | Transaction amount |
| Currency | Select | Yes | Defaults to source company's base currency |
| Description | Text | Yes | e.g., "Q4 2026 management fee" |
| Debit Account | Account picker | Yes | Account to debit on the source company (e.g., 1130 IC Receivables) |
| Credit Account | Account picker | Yes | Account to credit on the source company (e.g., 4500 IC Management Fee Income) |
| Posting Date | Date | Yes | Defaults to today |

**Behavior:**

1. User fills in the form and submits
2. System creates a journal entry on the source company with the specified debit/credit accounts
3. Sets `intercompanyPartnerId` on both journal lines
4. Creates an `intercompanyTransaction` record with `status = 'Unmatched'`
5. The counterparty company must then create their side of the transaction (either via invoice or another generic IC transaction) for matching to succeed
6. Redirects back to the IC transaction list with a success toast

**Validation:**

- Source and target company must be different
- Both must be in the same company group
- Neither can be the elimination entity
- Amount must be positive
- Debit and credit accounts must exist on the source company's chart of accounts

### UI Behavior

1. **Transaction list:** Shows all IC transactions with filters for status. Columns: source company, target company, amount, currency, document/description, status badge, matched date. A "New IC Transaction" button in the header opens the generic form.

2. **"Run Matching" button:** Calls the matching RPC. Refreshes the table. Shows a toast with results ("12 transactions matched, 3 unmatched").

3. **"Generate Eliminations" button:** Only enabled when all transactions are Matched (or user confirms proceeding with unmatched). Calls the elimination RPC. Shows the resulting elimination journal.

4. **Balance matrix:** A grid where rows and columns are companies. Cell (A, B) shows how much A owes B. Diagonal is zero. Net should be zero after elimination.

## Data Flow

### Setup (Automated)

```
Admin creates Company B as a subsidiary of Company A
    |
    v
seed-company assigns Company B to Company A's companyGroup
    |
    v
Database trigger "company_sync_ic_partners" fires:
  - Creates customer "Company B" in Company A (intercompanyCompanyId = B)
  - Creates supplier "Company B" in Company A (intercompanyCompanyId = B)
  - Creates customer "Company A" in Company B (intercompanyCompanyId = A)
  - Creates supplier "Company A" in Company B (intercompanyCompanyId = A)
    |
    v
IC customers/suppliers are ready — no manual setup needed
```

### Path 1: Invoice-Based IC Transaction

```
Company A posts sales invoice to IC customer "Company B"
    |
    v
post-sales-invoice checks customer.intercompanyCompanyId != null
    |
    v
Posts to 1130 (IC Receivables) instead of 1110
Sets intercompanyPartnerId = companyB.id
Creates intercompanyTransaction (status: Unmatched)
    |
    v
Company B posts purchase invoice from IC supplier "Company A"
    |
    v
post-purchase-invoice checks supplier.intercompanyCompanyId != null
    |
    v
Posts to 2020 (IC Payables) instead of default AP
Sets intercompanyPartnerId = companyA.id
Creates intercompanyTransaction (status: Unmatched)
```

### Path 2: Generic IC Transaction (No Invoice)

```
Finance user opens Intercompany page, clicks "New IC Transaction"
    |
    v
Fills form: Source=A, Target=B, Amount=$10,000,
  Description="Q4 Management Fee",
  Debit=1130 IC Receivables, Credit=4500 IC Management Fee Income
    |
    v
System creates journal on Company A:
  DR 1130 IC Receivables    $10,000
  CR 4500 IC Mgmt Fee Income $10,000
  (both lines: intercompanyPartnerId = B)
Creates intercompanyTransaction (status: Unmatched)
    |
    v
Finance user switches to Company B, creates counterpart:
  Source=B, Target=A, Amount=$10,000,
  Debit=6500 IC Mgmt Fee Expense, Credit=2020 IC Payables
    |
    v
System creates journal on Company B with intercompanyTransaction
```

### Matching & Elimination (Both Paths)

```
Finance user opens Intercompany page, clicks "Run Matching"
    |
    v
matchIntercompanyTransactions RPC:
  - Finds A's receivable and B's payable for same amount/partner
  - Updates both to status: Matched
    |
    v
Finance user clicks "Generate Eliminations"
    |
    v
generateEliminationEntries RPC:
  - Creates journal on elimination entity
  - Reverses all matched IC entries
  - Updates status: Eliminated
    |
    v
Elimination entries visible in COA when filtering to elimination entity
Consolidated view (Phase 4) nets IC accounts to zero
```

## Acceptance Criteria

### Automated IC Partner Setup
- [ ] When a subsidiary joins a company group, IC customer and supplier records are auto-created in all sibling companies (and vice versa)
- [ ] Auto-created IC records have `intercompanyCompanyId` set to the counterpart company
- [ ] Renaming a company updates all IC customer/supplier names across siblings
- [ ] Removing a company from a group cleans up its IC customer/supplier records
- [ ] IC customers/suppliers cannot be deleted by users (blocked by trigger)
- [ ] IC customers/suppliers are editable (payment terms, contacts, etc.)
- [ ] Elimination entities do not get IC customer/supplier records

### IC Detection on Posting
- [ ] `post-sales-invoice` detects IC transactions via `customer.intercompanyCompanyId != null`
- [ ] IC sales invoices use account 1130 (IC Receivables) instead of 1110
- [ ] `post-purchase-invoice` detects IC transactions via `supplier.intercompanyCompanyId != null`
- [ ] IC purchase invoices use account 2020 (IC Payables) instead of default AP
- [ ] `intercompanyPartnerId` is set on IC journal lines
- [ ] `intercompanyTransaction` rows created on posting with `status = 'Unmatched'`

### Generic IC Transactions
- [ ] Users can create IC transactions not tied to invoices (management fees, allocations, loans, etc.)
- [ ] Generic IC form validates source/target are different companies in the same group
- [ ] Generic IC transactions create journal entries with correct debit/credit and `intercompanyPartnerId`
- [ ] Generic IC transactions participate in matching just like invoice-originated ones

### Matching & Elimination
- [ ] Matching algorithm correctly pairs receivables with payables
- [ ] Unmatched transactions are surfaced with clear status in the UI
- [ ] Balance matrix shows correct IC balances between companies
- [ ] Elimination journal entries are generated on the elimination entity
- [ ] Elimination entries reverse the original IC entries (debit becomes credit and vice versa)
- [ ] After elimination, IC account balances net to zero in the consolidated view
- [ ] All elimination entries are immutable (append-only journal)
- [ ] Only users with `accounting_create` permission can trigger matching/elimination
- [ ] Partial matching is supported (some matched, some unmatched)
