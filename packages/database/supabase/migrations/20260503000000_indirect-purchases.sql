ALTER TABLE "purchaseOrderLine" ADD COLUMN "costCenterId" TEXT;
ALTER TABLE "purchaseOrderLine" ADD CONSTRAINT "purchaseOrderLine_costCenterId_fkey"
  FOREIGN KEY ("costCenterId") REFERENCES "costCenter"("id") ON DELETE SET NULL ON UPDATE CASCADE;
CREATE INDEX "purchaseOrderLine_costCenterId_idx" ON "purchaseOrderLine"("costCenterId");

ALTER TABLE "purchaseInvoiceLine" ADD COLUMN "costCenterId" TEXT;
ALTER TABLE "purchaseInvoiceLine" ADD CONSTRAINT "purchaseInvoiceLine_costCenterId_fkey"
  FOREIGN KEY ("costCenterId") REFERENCES "costCenter"("id") ON DELETE SET NULL ON UPDATE CASCADE;
CREATE INDEX "purchaseInvoiceLine_costCenterId_idx" ON "purchaseInvoiceLine"("costCenterId");

ALTER TABLE "supplierQuoteLine" ADD COLUMN "costCenterId" TEXT;
ALTER TABLE "supplierQuoteLine" ADD CONSTRAINT "supplierQuoteLine_costCenterId_fkey"
  FOREIGN KEY ("costCenterId") REFERENCES "costCenter"("id") ON DELETE SET NULL ON UPDATE CASCADE;
CREATE INDEX "supplierQuoteLine_costCenterId_idx" ON "supplierQuoteLine"("costCenterId");

ALTER TABLE "supplierQuoteLine" ADD COLUMN "accountId" TEXT;
ALTER TABLE "supplierQuoteLine" ADD CONSTRAINT "supplierQuoteLine_accountId_fkey"
  FOREIGN KEY ("accountId") REFERENCES "account"("id") ON DELETE SET NULL ON UPDATE CASCADE;
CREATE INDEX "supplierQuoteLine_accountId_idx" ON "supplierQuoteLine"("accountId");

ALTER TABLE "supplierQuoteLine" ADD COLUMN "supplierQuoteLineType" TEXT NOT NULL DEFAULT 'Part';

ALTER TABLE "supplierQuoteLine" ALTER COLUMN "itemId" DROP NOT NULL;
ALTER TABLE "supplierQuoteLine" ADD CONSTRAINT "supplierQuoteLine_itemId_check"
  CHECK (
    ("supplierQuoteLineType" = 'G/L Account') OR ("itemId" IS NOT NULL)
  );

ALTER TABLE "purchaseOrderLine" RENAME COLUMN "requestedDate" TO "requiredDate";
ALTER TABLE "purchaseInvoiceLine" ADD COLUMN "requiredDate" DATE;
ALTER TABLE "supplierQuoteLine" ADD COLUMN "requiredDate" DATE;
