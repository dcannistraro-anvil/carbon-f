# Phase 6: IC SO/PO Auto-Pairing

## Goal

When a purchase order is created against an intercompany supplier, automatically generate a matching sales order in the selling subsidiary. This is NetSuite's core "Automated Intercompany Management" feature.

## Current State

- `purchaseOrder` has `supplierId` FK → `supplier` has `intercompanyCompanyId` (set by auto-created IC supplier records)
- `salesOrder` has `customerId` FK → `customer` has `intercompanyCompanyId` (set by auto-created IC customer records)
- IC customers/suppliers are auto-created by `sync_intercompany_partners()` trigger when companies join a group
- Post-purchase-invoice and post-sales-invoice already detect IC and post to IC AR/AP accounts (1130, 2020)
- PO and SO both have `companyId` fields
- Both support revision tracking and status workflows

## Design

### Auto-Generation Flow

1. User creates PO in Company A against IC supplier "Company B"
2. On PO status transition to `'To Receive and Invoice'` or `'To Receive'` (i.e., when PO is confirmed/released):
   - System detects `supplier.intercompanyCompanyId IS NOT NULL`
   - Looks up the IC customer in Company B that represents Company A (`customer.intercompanyCompanyId = companyA.id`)
   - Creates a matching SO in Company B with that IC customer
   - Links PO ↔ SO via `intercompanyPurchaseOrderId` on the SO

### Line Mapping

| PO Line Field | SO Line Field |
|---------------|---------------|
| `itemId` | `itemId` (same shared item catalog) |
| `quantity` | `quantity` |
| `unitPrice` | `unitPrice` (same price — arm's-length uses PO price) |
| `description` | `description` |

### Schema Changes

```sql
-- Link SO back to the IC PO that generated it
ALTER TABLE "salesOrder"
  ADD COLUMN "intercompanyPurchaseOrderId" TEXT REFERENCES "purchaseOrder"("id");

-- Index for lookup
CREATE INDEX idx_sales_order_ic_po ON "salesOrder"("intercompanyPurchaseOrderId")
  WHERE "intercompanyPurchaseOrderId" IS NOT NULL;
```

### Status Sync

| Event | Source | Effect |
|-------|--------|--------|
| PO confirmed | Buyer | SO created in seller as `Confirmed` |
| PO received (receipt posted) | Buyer | SO updated to `In Progress` |
| SO shipped (shipment posted) | Seller | PO line received quantities updated |
| PO invoiced | Buyer | IC transaction created (existing logic) |
| SO invoiced | Seller | IC transaction created (existing logic) |
| PO cancelled | Buyer | SO cancelled if not yet shipped |
| SO cancelled | Seller | Warning on PO (can't auto-cancel a PO) |

### Implementation Approach

**Option A: Database trigger on PO status change**
- Pro: Catches all PO creation paths (UI, API, import)
- Con: Complex logic in Postgres, harder to debug

**Option B: Edge function called from PO service**
- Pro: TypeScript, easier to maintain, access to same shared utilities
- Con: Must be called from every PO creation path

**Recommendation: Option B** — Create a shared function `handleIntercompanyPurchaseOrder(purchaseOrderId)` called from the PO service when status transitions to a released state. The posting functions already follow this pattern.

### Transfer Pricing

- Default: PO unit price + weighted shipping cost (mirrors posting function logic)
- At-markup: Apply `markupPercent` on top of the base price
- Transfer price stored on SO lines as `unitPrice` — no separate field needed
- The markup configuration lives on the IC relationship (see Phase 8)

### Pairing UI

- PO detail page: Show "Paired IC Sales Order" link when `salesOrder.intercompanyPurchaseOrderId` matches
- SO detail page: Show "Generated from IC Purchase Order" link
- IC transaction list: Show document references for both sides

## Files to Modify

| File | Change |
|------|--------|
| New migration | Add `intercompanyPurchaseOrderId` to `salesOrder` |
| New edge function or shared utility | `handleIntercompanyPurchaseOrder()` |
| PO service/route | Call auto-pairing on status transition |
| PO detail UI | Show paired SO link |
| SO detail UI | Show source PO link |
| `accounting.models.ts` | Validator updates if needed |
