-- Backfill remainingQuantity on existing costLedger entries
-- Step 1: Set remainingQuantity = quantity on all inbound entries as baseline
UPDATE "costLedger" cl
SET "remainingQuantity" = cl."quantity"
WHERE cl."itemLedgerType" IN ('Purchase', 'Positive Adjmt.', 'Output', 'Transfer')
  AND cl."quantity" > 0;

-- Step 2: For FIFO items, consume layers oldest-first based on current on-hand
-- This DO block walks each (itemId, companyId) pair and adjusts remainingQuantity
DO $$
DECLARE
  r RECORD;
  on_hand NUMERIC;
  remaining_to_assign NUMERIC;
  layer RECORD;
BEGIN
  -- Process each item+company with FIFO costing
  FOR r IN
    SELECT ic."itemId", ic."companyId"
    FROM "itemCost" ic
    WHERE ic."costingMethod" = 'FIFO'
  LOOP
    -- Get current on-hand from itemLedger
    SELECT COALESCE(SUM(il."quantity"), 0) INTO on_hand
    FROM "itemLedger" il
    WHERE il."itemId" = r."itemId"
      AND il."companyId" = r."companyId";

    IF on_hand <= 0 THEN
      -- No inventory: zero out all layers
      UPDATE "costLedger"
      SET "remainingQuantity" = 0
      WHERE "itemId" = r."itemId"
        AND "companyId" = r."companyId";
      CONTINUE;
    END IF;

    -- Zero out all layers first
    UPDATE "costLedger"
    SET "remainingQuantity" = 0
    WHERE "itemId" = r."itemId"
      AND "companyId" = r."companyId";

    -- Walk newest-to-oldest (in FIFO, oldest are consumed first, so newest remain)
    remaining_to_assign := on_hand;
    FOR layer IN
      SELECT cl."id", cl."quantity"
      FROM "costLedger" cl
      WHERE cl."itemId" = r."itemId"
        AND cl."companyId" = r."companyId"
        AND cl."quantity" > 0
        AND cl."itemLedgerType" IN ('Purchase', 'Positive Adjmt.', 'Output', 'Transfer')
      ORDER BY cl."postingDate" DESC, cl."createdAt" DESC
    LOOP
      EXIT WHEN remaining_to_assign <= 0;

      IF layer."quantity" <= remaining_to_assign THEN
        UPDATE "costLedger" SET "remainingQuantity" = layer."quantity" WHERE "id" = layer."id";
        remaining_to_assign := remaining_to_assign - layer."quantity";
      ELSE
        UPDATE "costLedger" SET "remainingQuantity" = remaining_to_assign WHERE "id" = layer."id";
        remaining_to_assign := 0;
      END IF;
    END LOOP;

    -- Gap handling: if on_hand > costLedger total, create synthetic entry
    IF remaining_to_assign > 0 THEN
      INSERT INTO "costLedger" (
        "itemLedgerType", "costLedgerType", "adjustment", "documentType",
        "itemId", "quantity", "cost", "remainingQuantity", "companyId", "postingDate"
      )
      SELECT
        CASE
          WHEN i."replenishmentSystem" IN ('Make', 'Buy and Make') THEN 'Output'::"itemLedgerType"
          ELSE 'Purchase'::"itemLedgerType"
        END,
        'Direct Cost'::"costLedgerType",
        false,
        CASE
          WHEN i."replenishmentSystem" IN ('Make', 'Buy and Make') THEN 'Job Receipt'::"itemLedgerDocumentType"
          ELSE 'Purchase Receipt'::"itemLedgerDocumentType"
        END,
        r."itemId",
        remaining_to_assign,
        remaining_to_assign * COALESCE(ic."unitCost", ic."standardCost", 0),
        remaining_to_assign,
        r."companyId",
        COALESCE(
          (SELECT MIN(il."postingDate") FROM "itemLedger" il WHERE il."itemId" = r."itemId" AND il."companyId" = r."companyId"),
          CURRENT_DATE
        )
      FROM "itemCost" ic
      JOIN "item" i ON i."id" = ic."itemId"
      WHERE ic."itemId" = r."itemId"
        AND ic."companyId" = r."companyId";
    END IF;
  END LOOP;

  -- Process LIFO items (walk oldest-to-newest, since newest are consumed first)
  FOR r IN
    SELECT ic."itemId", ic."companyId"
    FROM "itemCost" ic
    WHERE ic."costingMethod" = 'LIFO'
  LOOP
    SELECT COALESCE(SUM(il."quantity"), 0) INTO on_hand
    FROM "itemLedger" il
    WHERE il."itemId" = r."itemId"
      AND il."companyId" = r."companyId";

    IF on_hand <= 0 THEN
      UPDATE "costLedger"
      SET "remainingQuantity" = 0
      WHERE "itemId" = r."itemId"
        AND "companyId" = r."companyId";
      CONTINUE;
    END IF;

    UPDATE "costLedger"
    SET "remainingQuantity" = 0
    WHERE "itemId" = r."itemId"
      AND "companyId" = r."companyId";

    remaining_to_assign := on_hand;
    FOR layer IN
      SELECT cl."id", cl."quantity"
      FROM "costLedger" cl
      WHERE cl."itemId" = r."itemId"
        AND cl."companyId" = r."companyId"
        AND cl."quantity" > 0
        AND cl."itemLedgerType" IN ('Purchase', 'Positive Adjmt.', 'Output', 'Transfer')
      ORDER BY cl."postingDate" ASC, cl."createdAt" ASC
    LOOP
      EXIT WHEN remaining_to_assign <= 0;

      IF layer."quantity" <= remaining_to_assign THEN
        UPDATE "costLedger" SET "remainingQuantity" = layer."quantity" WHERE "id" = layer."id";
        remaining_to_assign := remaining_to_assign - layer."quantity";
      ELSE
        UPDATE "costLedger" SET "remainingQuantity" = remaining_to_assign WHERE "id" = layer."id";
        remaining_to_assign := 0;
      END IF;
    END LOOP;

    IF remaining_to_assign > 0 THEN
      INSERT INTO "costLedger" (
        "itemLedgerType", "costLedgerType", "adjustment", "documentType",
        "itemId", "quantity", "cost", "remainingQuantity", "companyId", "postingDate"
      )
      SELECT
        CASE
          WHEN i."replenishmentSystem" IN ('Make', 'Buy and Make') THEN 'Output'::"itemLedgerType"
          ELSE 'Purchase'::"itemLedgerType"
        END,
        'Direct Cost'::"costLedgerType",
        false,
        CASE
          WHEN i."replenishmentSystem" IN ('Make', 'Buy and Make') THEN 'Job Receipt'::"itemLedgerDocumentType"
          ELSE 'Purchase Receipt'::"itemLedgerDocumentType"
        END,
        r."itemId",
        remaining_to_assign,
        remaining_to_assign * COALESCE(ic."unitCost", ic."standardCost", 0),
        remaining_to_assign,
        r."companyId",
        COALESCE(
          (SELECT MIN(il."postingDate") FROM "itemLedger" il WHERE il."itemId" = r."itemId" AND il."companyId" = r."companyId"),
          CURRENT_DATE
        )
      FROM "itemCost" ic
      JOIN "item" i ON i."id" = ic."itemId"
      WHERE ic."itemId" = r."itemId"
        AND ic."companyId" = r."companyId";
    END IF;
  END LOOP;
END $$;
