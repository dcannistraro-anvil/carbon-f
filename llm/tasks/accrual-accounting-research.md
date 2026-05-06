# Accrual Accounting Research: NetSuite & SAP Best Practices

## Key Consensus: Both Systems Agree On These Patterns

### 1. COGS at Shipment, Revenue at Invoice
- **NetSuite**: COGS posted at Item Fulfillment (shipment), NOT at invoice
- **SAP S/4HANA**: COGS posted at Goods Issue (PGI), NOT at billing
- **Both**: Invoice only posts revenue side (DR Accounts Receivable, CR Revenue)
- **Rationale**: Inventory physically leaves at shipment; cost must follow the goods

### 2. Clearing Accounts Bridge Timing Gaps
- **NetSuite**: No clearing account on sales side (COGS direct at fulfillment)
- **SAP S/4HANA**: No clearing on sales side either (COGS direct at PGI)
- **SAP B1**: Optional "Shipped Goods" clearing account to match COGS with revenue timing
- **Both (Purchase Side)**: GR/IR clearing account bridges receipt-to-invoice gap (Carbon already does this)

### 3. Manufacturing: WIP → Finished Goods → Variance
- **NetSuite**: Issue components → WIP Account → Complete → FG Inventory → Close → Variance
- **SAP**: Issue components → Production Order → GR → FG Inventory → Settlement → WIP or Variance
- **Both**: FG valued at standard cost at completion; variance settled separately
- **Key rule (SAP)**: WIP and Variance are never calculated simultaneously on same order

### 4. Dimensions Flow From Source Documents
- **NetSuite**: Department, Class, Location on each GL line; inherited from parent transaction
- **SAP**: Cost Center/Profit Center derived from material master or source document
- **Both**: Automated postings carry dimensions automatically, not manually assigned

---

## Shipment Journal Entries

### Normal Flow: Ship First, Invoice Later

**At Shipment:**
| Account | Debit | Credit |
|---------|-------|--------|
| Cost of Goods Sold | $X | |
| Inventory Asset | | $X |

**At Invoice:**
| Account | Debit | Credit |
|---------|-------|--------|
| Accounts Receivable | $Y | |
| Sales Revenue | | $Y |

### Invoice First, Ship Later

**At Invoice** (NetSuite): Only DR AR / CR Revenue. No COGS until fulfillment.
**At Shipment**: DR COGS / CR Inventory as normal.

**SAP B1 Alternative** (Shipped Goods Account):
- At Delivery: DR Shipped Goods / CR Inventory
- At Invoice: DR COGS / CR Shipped Goods + DR AR / CR Revenue
- Ensures COGS and Revenue match in same period

---

## COGS Calculation by Costing Method

### Standard Cost
- COGS = standard cost × quantity shipped (always)
- Variance at purchase: DR/CR Purchase Price Variance
- Variance at production: DR Production Variance / CR Production Order Settlement
- Inventory always valued at standard cost

### Average Cost
- COGS = current weighted average × quantity shipped
- Average = (Total stock value) / (Total stock quantity)
- Recalculated after every receipt
- No cost layers; single blended cost

### FIFO (First-In, First-Out)
- COGS uses cost of oldest receipt layer first
- Each receipt creates a cost layer with quantity and unit cost
- Layers consumed oldest-first; when layer exhausted, move to next
- Ending inventory valued at most recent costs

### LIFO (Last-In, First-Out)
- COGS uses cost of most recent receipt layer first
- Same layer tracking as FIFO, consumed in reverse order
- Ending inventory valued at oldest costs

### Cost Layer Requirements
| Method | Layers Needed | Layer Data |
|--------|--------------|------------|
| Standard | None | Just the standard cost from itemCost |
| Average | None | Running total cost / total quantity |
| FIFO | Per-receipt layers | Remaining quantity + unit cost, ordered by date ASC |
| LIFO | Per-receipt layers | Remaining quantity + unit cost, ordered by date DESC |

---

## Manufacturing Accounting

### Component Issue (to WIP)
| Account | Debit | Credit |
|---------|-------|--------|
| WIP Account | $X | |
| Raw Material Inventory | | $X |

### Finished Goods Receipt (job completion)
| Account | Debit | Credit |
|---------|-------|--------|
| Finished Goods Inventory | $Y (at standard cost) | |
| WIP Account | | $Y |

### Variance Settlement (job close)
| Account | Debit | Credit |
|---------|-------|--------|
| Production Variance | $V | |
| Scrap | $S | |
| WIP Account | | $V + $S |

### Variance Types (SAP)
- **Input Price Variance**: Actual material/activity prices ≠ planned
- **Input Quantity Variance**: Actual consumption ≠ BOM quantities
- **Lot Size Variance**: Fixed costs not fully absorbed due to qty difference
- **Mix Variance**: Different input mix than planned

### NetSuite WIP Compatibility
- Only Standard Cost and Average Cost assemblies support WIP
- FIFO/LIFO assemblies do NOT support WIP tracking
- Components can use any costing method

---

## Dimension Inheritance Patterns

### NetSuite
- 3 built-in: Department, Class, Location
- Applied at line level (when enabled) or header level
- Child transactions inherit from parent (SO → Fulfillment → Invoice)
- Location on fulfillment may come from warehouse rather than SO header
- Custom segments can extend dimensional model

### SAP
- Cost Center: From OKB9 defaults or document account assignment
- Profit Center: From material master (material + plant) or cost center assignment
- Account Assignment Category on PO controls: inventory vs direct consumption
- Automatic derivation from source document chain

### Pattern for Carbon
Dimensions should be derived from:
1. **Item**: ItemPostingGroup (already on receipts/PO invoices)
2. **Location**: From shipment/receipt location
3. **Customer/Supplier**: CustomerType or SupplierType
4. **Cost Center**: From sales order line, PO line, or job
5. **Department**: From employee or org structure (future)
