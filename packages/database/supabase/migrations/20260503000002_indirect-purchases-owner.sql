ALTER TABLE "costCenter" ADD COLUMN "ownerId" TEXT;
ALTER TABLE "costCenter" ADD CONSTRAINT "costCenter_ownerId_fkey"
  FOREIGN KEY ("ownerId") REFERENCES "user"("id") ON DELETE SET NULL ON UPDATE CASCADE;
CREATE INDEX "costCenter_ownerId_idx" ON "costCenter"("ownerId");

ALTER TABLE "purchaseOrderLine" ADD COLUMN "ownerId" TEXT;
ALTER TABLE "purchaseOrderLine" ADD CONSTRAINT "purchaseOrderLine_ownerId_fkey"
  FOREIGN KEY ("ownerId") REFERENCES "user"("id") ON DELETE SET NULL ON UPDATE CASCADE;
CREATE INDEX "purchaseOrderLine_ownerId_idx" ON "purchaseOrderLine"("ownerId");

ALTER TABLE "purchaseInvoiceLine" ADD COLUMN "ownerId" TEXT;
ALTER TABLE "purchaseInvoiceLine" ADD CONSTRAINT "purchaseInvoiceLine_ownerId_fkey"
  FOREIGN KEY ("ownerId") REFERENCES "user"("id") ON DELETE SET NULL ON UPDATE CASCADE;
CREATE INDEX "purchaseInvoiceLine_ownerId_idx" ON "purchaseInvoiceLine"("ownerId");

ALTER TABLE "supplierQuoteLine" ADD COLUMN "ownerId" TEXT;
ALTER TABLE "supplierQuoteLine" ADD CONSTRAINT "supplierQuoteLine_ownerId_fkey"
  FOREIGN KEY ("ownerId") REFERENCES "user"("id") ON DELETE SET NULL ON UPDATE CASCADE;
CREATE INDEX "supplierQuoteLine_ownerId_idx" ON "supplierQuoteLine"("ownerId");
