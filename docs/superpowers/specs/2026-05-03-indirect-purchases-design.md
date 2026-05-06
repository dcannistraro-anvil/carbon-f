# Indirect Purchases

## Overview

Add support for indirect purchases (GL Account lines) alongside existing direct purchases (Part, Material, Tool, Consumable) in purchase orders, purchase invoices, and supplier quotes. A single document can mix both direct and indirect lines.

## Line Form UI

### PurchaseOrderLineForm

Tabs inside the ModalCard (same pattern as JobForm's Single/Many tabs):

- **"Direct" tab** — existing form, unchanged. Item selector with type switching (Part, Material, Tool, Consumable), UOM, conversion factor, location, shelf, quantity, pricing, tax.
- **"Indirect" tab** — new form. Fields: GL Account selector, Description (free text), Cost Center (new creatable combobox), Quantity, Unit Price, Shipping, Tax Amount, Tax Percent. No item, no UOM, no conversion factor, no location/shelf.

The "Indirect" tab sets `purchaseOrderLineType` to `"G/L Account"` via a hidden field.

When **editing** an existing line, the tab defaults to the line's type and tabs are hidden (same as JobForm hides tabs when editing). Tabs only show when creating a new line.

### PurchaseOrderExplorer

Both line types appear in the same list. GL Account lines display the account name/description instead of an item readable ID.

### PurchaseInvoiceLineForm

Same Direct/Indirect tab treatment as the purchase order line form.

### Supplier Quote Line Form

Same Direct/Indirect tab treatment.

## CostCenter Component

New component at `apps/erp/app/components/Form/CostCenter.tsx`:

- Creatable combobox pattern (matching existing form components)
- Fetches options from `api/accounting.cost-centers`
- Allows inline creation of new cost centers
- Standard props: `name`, `label`, `value`, `onChange`, `isOptional`

## Validators & Models

### purchasing.models.ts

- Add `"G/L Account"` to `purchaseOrderLineType`
- Add `accountId` and `costCenterId` fields to `purchaseOrderLineValidator`
- Refinement: `purchaseOrderLineType === "G/L Account"` requires `accountId`, forbids `itemId`; direct types require `itemId`, forbid `accountId`

### invoicing.models.ts

- Same changes to `purchaseInvoiceLineType` and `purchaseInvoiceLineValidator`

### DB Migration

- Add `costCenterId` column (FK to `costCenter`) on `purchaseOrderLine` and `purchaseInvoiceLine`
- Verify `accountId` column exists on both tables (should exist from accounting dimensions work)

## Status Logic & Receipts

### Status Determination

The utils that calculate PO status become line-type-aware:

- GL Account lines are treated as always fully received (zero contribution to "to receive" count)
- PO with **only** GL Account lines: status goes directly to "To Invoice" after finalization
- PO with **mixed** lines: "to receive" count only comes from direct lines; if all direct lines are received but indirect lines remain uninvoiced, status is "To Invoice"
- All lines (both types) invoiced: status becomes "Completed"

### Receipts

- Receipt creation from a PO filters out GL Account lines
- GL Account lines do not appear in the receipt line list
- If PO has only GL Account lines, the "Receive" button is hidden/disabled

### Purchase Invoice Creation from PO

Both direct and indirect lines are included. GL Account lines carry over `accountId`, `costCenterId`, and description.

## Posting & Accounting

### Purchase Invoice Posting — Indirect Lines

- **Debit:** GL account specified on the line (`accountId`) — directly, bypassing posting groups
- **Credit:** Accounts Payable (same as direct lines)
- Tax, shipping, and discount handling unchanged

### Direct Lines

Posting continues through posting groups — no changes.

### Mixed Invoices

Journal entries contain a mix: some lines debit through posting groups (direct), some debit the explicit GL account (indirect).

## Purchase Order PDF

- Indirect lines show **description** as the primary content (same column as item name for direct lines)
- Account name/number shown as secondary muted text beneath the description
- No item number / part number for indirect lines
- Quantity, unit price, extended price columns remain the same
- Cost center is not shown on the PDF (internal-only detail)
- Mixed POs: direct and indirect lines interleaved in natural order, no separate sections

## Supplier Quotes

- Supplier quote line form gets the same Direct/Indirect tab treatment
- GL Account lines on quotes carry over `accountId`, `costCenterId`, and description when converting to a purchase order

## Document Conversion Edge Functions

The edge functions that convert between documents (supplier quote to PO, PO to invoice, etc.) must carry over GL Account fields:

- `purchaseOrderLineType` / `invoiceLineType` (preserving `"G/L Account"`)
- `accountId`
- `costCenterId`
- `description`

These fields must be mapped alongside the existing item-based fields during conversion. For GL Account lines, item-specific fields (`itemId`, `conversionFactor`, UOM codes) are left null/empty.

## Standalone Purchase Invoices

- Purchase invoices can be created with GL Account lines without a backing PO
- Posting logic is the same regardless of origin (from PO or standalone)
