# Journal Entries — Implementation Plan (V1)

## Context

Adding a Manual Journal Entries submodule under Accounting > Manage. Accountants need a way to create manual GL adjustments (accruals, corrections, reclassifications, etc.) with debit/credit lines that must balance to zero. On posting, lines write to the existing immutable `journal`/`journalLine` GL tables.

The route structure follows the **shipment/receipt pattern**: a list route under `accounting+/journals.tsx` and a dedicated detail route group at `journal-entry+/` with its own layout, header, and detail views.

## Key Design Decisions

- **Separate tables**: `journalEntry` (header) + `journalEntryLine` (lines) are draft-editable. Posting writes to `journal`/`journalLine` and locks the entry.
- **Company from session**: Logged-in company used automatically — no subsidiary picker.
- **Document type**: Optional Postgres enum for categorization.
- **Route split**: List at `accounting+/journals.tsx`, detail at `journal-entry+/$journalEntryId.tsx` (like shipment pattern).
- **New JE via drawer**: The "new" route is a child of the journals list, rendered as a Drawer overlay (per feedback convention).

---

## Step 1: Database Migration

**File**: `packages/database/supabase/migrations/YYYYMMDDHHMMSS_journal-entries.sql`

### Enums

```sql
CREATE TYPE "journalEntryType" AS ENUM ('Accrual', 'Correction', 'Reclassification', 'Depreciation', 'Other');
CREATE TYPE "journalEntryStatus" AS ENUM ('Draft', 'Posted');
```

### Tables

```sql
CREATE TABLE "journalEntry" (
  "id" TEXT NOT NULL DEFAULT id('je'),
  "journalEntryId" TEXT NOT NULL,          -- human-readable (JE-0001)
  "companyId" TEXT NOT NULL REFERENCES "company"("id"),
  "companyGroupId" TEXT NOT NULL,
  "description" TEXT,
  "postingDate" DATE NOT NULL DEFAULT CURRENT_DATE,
  "accountingPeriodId" TEXT REFERENCES "accountingPeriod"("id"),
  "entryType" "journalEntryType",
  "status" "journalEntryStatus" NOT NULL DEFAULT 'Draft',
  "journalId" INTEGER REFERENCES "journal"("id"),
  "reversalOfId" TEXT REFERENCES "journalEntry"("id"),
  "postedAt" TIMESTAMP WITH TIME ZONE,
  "postedBy" TEXT,
  "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  "createdBy" TEXT NOT NULL,
  "updatedAt" TIMESTAMP WITH TIME ZONE,
  "updatedBy" TEXT,
  "customFields" JSONB,
  CONSTRAINT "journalEntry_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "journalEntry_journalEntryId_companyId_key" UNIQUE ("journalEntryId", "companyId")
);

CREATE TABLE "journalEntryLine" (
  "id" TEXT NOT NULL DEFAULT id('jel'),
  "journalEntryId" TEXT NOT NULL REFERENCES "journalEntry"("id") ON DELETE CASCADE,
  "accountNumber" TEXT NOT NULL,
  "companyGroupId" TEXT NOT NULL,
  "description" TEXT,
  "debit" NUMERIC(19,4) NOT NULL DEFAULT 0,
  "credit" NUMERIC(19,4) NOT NULL DEFAULT 0,
  "dimensionValues" JSONB,
  "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  "createdBy" TEXT NOT NULL,
  "updatedAt" TIMESTAMP WITH TIME ZONE,
  "updatedBy" TEXT,
  "customFields" JSONB,
  CONSTRAINT "journalEntryLine_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "journalEntryLine_accountNumber_fkey"
    FOREIGN KEY ("accountNumber", "companyGroupId") REFERENCES "account"("number", "companyGroupId"),
  CONSTRAINT "journalEntryLine_debit_credit_check" CHECK ("debit" >= 0 AND "credit" >= 0),
  CONSTRAINT "journalEntryLine_debit_or_credit_check" CHECK (NOT ("debit" > 0 AND "credit" > 0))
);
```

### Indexes

```sql
CREATE INDEX "journalEntry_companyId_idx" ON "journalEntry" ("companyId");
CREATE INDEX "journalEntry_status_idx" ON "journalEntry" ("status", "companyId");
CREATE INDEX "journalEntry_postingDate_idx" ON "journalEntry" ("postingDate", "companyId");
CREATE INDEX "journalEntryLine_journalEntryId_idx" ON "journalEntryLine" ("journalEntryId");
```

### RLS Policies

Follow conventions from `feedback_rls_pattern.md`:
- Policy names: `"SELECT"`, `"INSERT"`, `"UPDATE"`, `"DELETE"`
- `journalEntry`: company-scoped using `get_companies_with_employee_role()` for SELECT, `get_companies_with_employee_permission('accounting_create')` etc. for mutations
- `journalEntryLine`: same pattern scoped via `companyGroupId` using `get_company_groups_for_employee()` / `get_company_groups_for_root_permission('accounting_*')`
- Reference: `20260228024512_dimensions.sql` for group-scoped RLS pattern

### View

```sql
CREATE OR REPLACE VIEW "journalEntries" AS
  SELECT je.*,
    COALESCE(SUM(jel."debit"), 0) AS "totalDebits",
    COALESCE(SUM(jel."credit"), 0) AS "totalCredits",
    COUNT(jel."id")::integer AS "lineCount"
  FROM "journalEntry" je
  LEFT JOIN "journalEntryLine" jel ON jel."journalEntryId" = je."id"
  GROUP BY je."id";
```

---

## Step 2: Models & Validators

**File**: `apps/erp/app/modules/accounting/accounting.models.ts`

Add:
- `journalEntryTypes` const array
- `journalEntryStatuses` const array
- `journalEntryValidator` — postingDate (required), description, entryType (optional enum)
- `journalEntryLineValidator` — accountNumber (required), debit (>=0), credit (>=0), description; refine: not both >0, at least one >0

---

## Step 3: Service Functions

**File**: `apps/erp/app/modules/accounting/accounting.service.ts`

Add functions:
- `getJournalEntries(client, companyId, filters)` — query `journalEntries` view with GenericQueryFilters
- `getJournalEntry(client, id)` — single entry with lines joined
- `createJournalEntry(client, data)` — insert header, return id
- `updateJournalEntry(client, data)` — update Draft only
- `deleteJournalEntry(client, id)` — delete Draft only
- `upsertJournalEntryLine(client, data)` — create or update line
- `deleteJournalEntryLine(client, id)` — delete line
- `postJournalEntry(client, id, userId)`:
  1. Fetch entry + lines
  2. Assert status=Draft, SUM(debit)=SUM(credit), lines exist
  3. Insert `journal` header → get journalId
  4. Insert `journalLine` rows (amount = debit - credit per line)
  5. Insert `journalLineDimension` rows from dimensionValues JSONB
  6. Update journalEntry: status=Posted, journalId, postedAt, postedBy
- `reverseJournalEntry(client, id, userId)`:
  1. Fetch posted entry + lines
  2. Create new Draft journalEntry with reversalOfId, swapped debit/credit on lines

---

## Step 4: Types

**File**: `apps/erp/app/modules/accounting/types.ts`

Add types derived from service return types:
- `JournalEntry`, `JournalEntryListItem`, `JournalEntryLine`

---

## Step 5: Path Definitions

**File**: `apps/erp/app/utils/path.ts`

Existing: `accountingJournals: \`${x}/accounting/journals\``

Add:
```typescript
journalEntry: (id: string) => generatePath(`${x}/journal-entry/${id}`),
journalEntryDetails: (id: string) => generatePath(`${x}/journal-entry/${id}/details`),
newJournalEntry: `${x}/accounting/journals/new`,
deleteJournalEntry: (id: string) => generatePath(`${x}/journal-entry/${id}/delete`),
postJournalEntry: (id: string) => generatePath(`${x}/journal-entry/${id}/post`),
reverseJournalEntry: (id: string) => generatePath(`${x}/journal-entry/${id}/reverse`),
newJournalEntryLine: (id: string) => generatePath(`${x}/journal-entry/${id}/lines/new`),
deleteJournalEntryLine: (lineId: string) => generatePath(`${x}/journal-entry/lines/${lineId}/delete`),
```

---

## Step 6: Routes

### List route (under accounting layout)

| File | Purpose |
|------|---------|
| `routes/x+/accounting+/journals.tsx` | List view — table + `<Outlet />` for new drawer |
| `routes/x+/accounting+/journals.new.tsx` | New JE — **Drawer overlay** with header fields, creates entry, redirects to detail |

### Detail route group (dedicated layout, like shipment)

| File | Purpose |
|------|---------|
| `routes/x+/journal-entry+/_layout.tsx` | Simple `<Outlet />` wrapper with breadcrumb + meta |
| `routes/x+/journal-entry+/$journalEntryId.tsx` | Container: PanelProvider + Header + scrollable VStack + `<Outlet />` |
| `routes/x+/journal-entry+/$journalEntryId._index.tsx` | Redirect to details |
| `routes/x+/journal-entry+/$journalEntryId.details.tsx` | Form + Lines component + Summary bar |
| `routes/x+/journal-entry+/$journalEntryId.post.tsx` | Post action route |
| `routes/x+/journal-entry+/$journalEntryId.reverse.tsx` | Reverse action route |
| `routes/x+/journal-entry+/$journalEntryId.delete.tsx` | Delete action route (Draft only) |
| `routes/x+/journal-entry+/lines.new.tsx` | Add line action route |
| `routes/x+/journal-entry+/lines.$lineId.tsx` | Edit line — Drawer overlay |
| `routes/x+/journal-entry+/lines.$lineId.delete.tsx` | Delete line action route |

### Key layout pattern (from shipment)

```
_layout.tsx → simple Outlet wrapper
$journalEntryId.tsx →
  <PanelProvider>
    <div className="flex flex-col h-[calc(100dvh-49px)] overflow-hidden w-full">
      <JournalEntryHeader />  {/* ID, status badge, Post/Reverse/Delete buttons */}
      <div className="flex h-[calc(100dvh-99px)] overflow-y-auto scrollbar-hide w-full">
        <VStack spacing={4} className="h-full p-2 w-full max-w-5xl mx-auto">
          <Outlet />
        </VStack>
      </div>
    </div>
  </PanelProvider>

$journalEntryId.details.tsx →
  <div className="flex flex-col gap-2 pb-16 w-full">
    <JournalEntryForm />     {/* Card: postingDate, description, entryType */}
    <JournalEntryLines />    {/* Card: line items table with add/edit/delete */}
    <JournalEntrySummary />  {/* Debit/credit totals, balance indicator */}
  </div>
```

---

## Step 7: UI Components

**Directory**: `apps/erp/app/modules/accounting/ui/JournalEntries/`

| Component | Description |
|-----------|-------------|
| `JournalEntriesTable.tsx` | List table: ID (linked), date, description, type, status badge, totalDebits, totalCredits, lineCount |
| `JournalEntryHeader.tsx` | Header bar: ID with copy, status badge, Post/Reverse/Delete action buttons. Follow `ShipmentHeader` pattern. |
| `JournalEntryForm.tsx` | Card form: postingDate (DatePicker), description (Input), entryType (Select, optional). Disabled when Posted. |
| `JournalEntryLines.tsx` | Card with line items table. Columns: account (Combobox), description, debit, credit, dimensions, actions. Add line button. Disabled when Posted. |
| `JournalEntryLineForm.tsx` | Drawer for add/edit line: account picker (filtered non-group accounts), debit/credit (mutually exclusive input), description, dimension selectors per active dimension. |
| `JournalEntrySummary.tsx` | Footer card: Total Debits / Total Credits / Difference. Red when unbalanced, green when balanced. |
| `index.ts` | Barrel exports |

### UX details
- Debit/credit inputs: entering debit clears credit and vice versa
- Post button disabled when: no lines, unbalanced, or already Posted
- Posted entries: all fields read-only, only Reverse action available
- Account picker: filtered to non-group accounts in the company group
- Each active dimension gets a selector in the line form (Combobox of dimension values)

---

## Step 8: Sidebar Navigation

**File**: `apps/erp/app/modules/accounting/ui/useAccountingSubmodules.tsx`

Uncomment/replace the commented "Journals" entry in the Manage group:

```typescript
{
  name: "Journal Entries",
  to: path.to.accountingJournals,
  role: "employee",
  icon: <LuBookOpen />
}
```

---

## Step 9: Exports

**File**: `apps/erp/app/modules/accounting/index.ts`

Export new validators, service functions, types, and constants.

---

## File Change Summary

| Area | Files | Action |
|------|-------|--------|
| Migration | `packages/database/supabase/migrations/YYYYMMDD_journal-entries.sql` | New |
| Models | `accounting.models.ts` | Modify |
| Service | `accounting.service.ts` | Modify |
| Types | `types.ts` | Modify |
| Paths | `path.ts` | Modify |
| List routes | `accounting+/journals.tsx`, `journals.new.tsx` | New (2) |
| Detail routes | `journal-entry+/_layout.tsx`, `$journalEntryId.tsx`, `$journalEntryId._index.tsx`, `$journalEntryId.details.tsx`, `$journalEntryId.post.tsx`, `$journalEntryId.reverse.tsx`, `$journalEntryId.delete.tsx`, `lines.new.tsx`, `lines.$lineId.tsx`, `lines.$lineId.delete.tsx` | New (10) |
| UI components | `JournalEntries/` directory (7 files) | New |
| Nav | `useAccountingSubmodules.tsx` | Modify |
| Exports | `index.ts` | Modify |
| DB Types | `packages/database/src/types.ts` | Regenerated |

**Total: ~19 new files, ~6 modified files**

---

## Verification

1. **Migration**: Run migration, verify tables/enums/view/RLS exist in Supabase
2. **Navigation**: Confirm "Journal Entries" appears under Accounting > Manage
3. **List view**: Navigate to journals, verify empty table renders with "New" button
4. **Create**: Click New, fill header fields in drawer, save → redirects to detail view
5. **Add lines**: Add 2+ lines with debit/credit, verify summary totals update
6. **Balance check**: Try to post when unbalanced → button disabled / error shown
7. **Post**: Balance entry, click Post → verify status changes to Posted, journal/journalLine records created in GL
8. **Immutability**: Verify all fields are read-only after posting, edit/delete actions hidden
9. **Reverse**: Click Reverse on posted entry → new Draft JE created with flipped amounts
10. **Dimensions**: Add dimension values to lines, post, verify `journalLineDimension` records created
