-- Add remainingQuantity to costLedger for FIFO/LIFO cost layers
ALTER TABLE "costLedger"
  ADD COLUMN IF NOT EXISTS "remainingQuantity" NUMERIC(12, 4) NOT NULL DEFAULT 0;

CREATE INDEX "costLedger_itemId_remainingQuantity_idx"
  ON "costLedger" ("itemId", "remainingQuantity")
  WHERE "remainingQuantity" > 0;

-- Add new document types used by accrual accounting journal entries
ALTER TYPE "journalLineDocumentType" ADD VALUE IF NOT EXISTS 'Sales Shipment';
ALTER TYPE "journalLineDocumentType" ADD VALUE IF NOT EXISTS 'Transfer Shipment';
ALTER TYPE "journalLineDocumentType" ADD VALUE IF NOT EXISTS 'Purchase Receipt';
ALTER TYPE "journalLineDocumentType" ADD VALUE IF NOT EXISTS 'Purchase Invoice';
ALTER TYPE "journalLineDocumentType" ADD VALUE IF NOT EXISTS 'Job Consumption';
ALTER TYPE "journalLineDocumentType" ADD VALUE IF NOT EXISTS 'Job Receipt';
ALTER TYPE "journalLineDocumentType" ADD VALUE IF NOT EXISTS 'Batch Split';
ALTER TYPE "journalLineDocumentType" ADD VALUE IF NOT EXISTS 'Maintenance Consumption';
ALTER TYPE "journalLineDocumentType" ADD VALUE IF NOT EXISTS 'Production Event';
ALTER TYPE "journalLineDocumentType" ADD VALUE IF NOT EXISTS 'Job Close';

-- Add new source types used by accrual accounting journal entries
ALTER TYPE "journalEntrySourceType" ADD VALUE IF NOT EXISTS 'Job Consumption';
ALTER TYPE "journalEntrySourceType" ADD VALUE IF NOT EXISTS 'Job Receipt';
ALTER TYPE "journalEntrySourceType" ADD VALUE IF NOT EXISTS 'Production Event';
ALTER TYPE "journalEntrySourceType" ADD VALUE IF NOT EXISTS 'Job Close';

-- Add postedToGL flag to productionEvent for idempotent labor absorption posting
ALTER TABLE "productionEvent" ADD COLUMN IF NOT EXISTS "postedToGL" BOOLEAN NOT NULL DEFAULT FALSE;
