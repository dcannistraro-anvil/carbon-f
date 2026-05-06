# Phase 8: IC Inventory Transfers

## Goal

Support inventory transfers between companies in the same group, both at-cost (non-arm's-length) and at-markup (arm's-length), with proper GL entries and IC transaction tracking.

## Current State

- `warehouseTransfer` handles between-location transfers within a single company
- `post-stock-transfer` creates `itemLedger` entries only (no GL)
- `stockTransfer` handles within-location shelf-to-shelf transfers
- Neither supports cross-company transfers
- IC PO/SO auto-pairing (Phase 6) will exist for arm's-length workflow

## Design

### At-Cost (Non-Arm's-Length) Transfers

These are direct inventory movements between companies with no markup. The item stays at the same cost.

#### Schema Changes

```sql
-- Extend warehouseTransfer for IC support
ALTER TABLE "warehouseTransfer"
  ADD COLUMN "transferPricingMethod" TEXT DEFAULT 'AtCost'
    CHECK ("transferPricingMethod" IN ('AtCost', 'AtMarkup')),
  ADD COLUMN "markupPercent" NUMERIC(10,4) DEFAULT 0;
```

Note: `warehouseTransfer` already has `fromLocationId` and `toLocationId`. Locations belong to companies. If the two locations belong to different companies in the same group, it's an IC transfer. No additional FK needed — we derive IC status from location ownership.

#### Posting Logic (extend `post-stock-transfer`)

When source location's company ≠ target location's company:

**Source company journal:**
| Account | Debit | Credit |
|---------|-------|--------|
| IC Transfer Out (new default account) | cost | |
| Inventory | | cost |

**Target company journal:**
| Account | Debit | Credit |
|---------|-------|--------|
| Inventory | cost | |
| IC Transfer In (new default account) | | cost |

**IC tracking:**
- Create `intercompanyTransaction` with status `Unmatched`
- Link source and target journal lines
- Standard matching/elimination flow handles the rest

#### New Account Defaults

- `intercompanyTransferOutAccount` (e.g., 4500)
- `intercompanyTransferInAccount` (e.g., 4501)

### At-Markup (Arm's-Length) Transfers

These simulate a real sale between companies. The selling company recognizes revenue and the buying company records at the marked-up cost.

#### Flow

1. User creates IC warehouse transfer with `transferPricingMethod = 'AtMarkup'` and `markupPercent = 10`
2. System calculates transfer price per line: `unitCost × (1 + markupPercent/100)` + weighted shipping cost
3. Instead of direct inventory transfer, system triggers the PO/SO auto-pairing workflow (Phase 6):
   - Creates PO in buying company at transfer price
   - Auto-generates SO in selling company (Phase 6 logic)
   - Standard PO receive → SO ship → invoice → post flow
4. Seller recognizes:
   - Revenue at transfer price
   - COGS at actual cost
   - Gain = markup amount (falls out naturally from revenue - COGS)
5. No separate gain/loss account needed — the standard sales/COGS accounts handle it
6. IC elimination removes the intercompany revenue and restates inventory at original cost in consolidated view

#### Gain/Loss in Consolidation

The markup creates artificial profit in the selling company. During elimination:
- IC Revenue is reversed
- IC COGS is reversed
- Net effect: inventory on the buyer's books is restated to original cost
- The unrealized profit in inventory is eliminated

This is handled by the standard elimination flow since IC revenue/COGS post to accounts flagged for elimination.

### UI Changes

- Warehouse transfer form: Show `transferPricingMethod` selector when source/target locations are in different companies
- If `AtMarkup`: show `markupPercent` field
- If `AtMarkup`: show info that this will create a PO/SO pair
- Warehouse transfer list: IC badge/indicator

### Validation

- Source and target locations must belong to companies in the same `companyGroup`
- `markupPercent` must be ≥ 0 (0 = at cost even with AtMarkup method, though AtCost is cleaner)
- Cannot create IC transfer if either company has no active accounting period

## Dependencies

- Phase 5 (period-close enforcement) — ensures transfers post to open periods
- Phase 6 (IC SO/PO auto-pairing) — required for at-markup workflow

## Files to Modify

| File | Change |
|------|--------|
| New migration | Add columns to `warehouseTransfer`, new account defaults |
| `post-stock-transfer/index.ts` | Add GL posting for IC transfers (at-cost) |
| Warehouse transfer service | IC detection, at-markup → PO/SO creation |
| Warehouse transfer form UI | Transfer pricing fields for IC |
| `accounting.models.ts` | Validators |
| `AccountDefaultsForm` | IC transfer accounts |
