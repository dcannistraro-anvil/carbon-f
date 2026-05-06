-- Tax Exemption Reason Enum
DO $$ BEGIN
  CREATE TYPE "taxExemptionReason" AS ENUM (
    'Resale',
    'Government',
    'Nonprofit',
    'Agriculture',
    'Industrial',
    'Export',
    'Medical',
    'Educational',
    'Religious',
    'Other'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Customer Tax Table (1:1 with customer)
CREATE TABLE IF NOT EXISTS "customerTax" (
  "customerId" TEXT NOT NULL,
  "taxId" TEXT,
  "vatNumber" TEXT,
  "eori" TEXT,
  "taxExempt" BOOLEAN NOT NULL DEFAULT FALSE,
  "taxExemptionReason" "taxExemptionReason",
  "taxExemptionCertificateNumber" TEXT,
  "taxExemptionCertificatePath" TEXT,
  "companyId" TEXT NOT NULL,
  "updatedAt" TIMESTAMP WITH TIME ZONE,
  "updatedBy" TEXT,

  CONSTRAINT "customerTax_pkey" PRIMARY KEY ("customerId"),
  CONSTRAINT "customerTax_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "customer"("id") ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "customerTax_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "company"("id") ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "customerTax_updatedBy_fkey" FOREIGN KEY ("updatedBy") REFERENCES "user"("id") ON UPDATE CASCADE ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS "customerTax_customerId_idx" ON "customerTax"("customerId");

ALTER TABLE "customerTax" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "SELECT" ON "public"."customerTax";
CREATE POLICY "SELECT" ON "public"."customerTax"
FOR SELECT USING (
  "companyId" = ANY (
    (SELECT get_companies_with_employee_permission('sales_view'))::text[]
  )
);

DROP POLICY IF EXISTS "UPDATE" ON "public"."customerTax";
CREATE POLICY "UPDATE" ON "public"."customerTax"
FOR UPDATE USING (
  "companyId" = ANY (
    (SELECT get_companies_with_employee_permission('sales_update'))::text[]
  )
);

-- Supplier Tax Table (1:1 with supplier)
CREATE TABLE IF NOT EXISTS "supplierTax" (
  "supplierId" TEXT NOT NULL,
  "taxId" TEXT,
  "vatNumber" TEXT,
  "eori" TEXT,
  "taxExempt" BOOLEAN NOT NULL DEFAULT FALSE,
  "taxExemptionReason" "taxExemptionReason",
  "taxExemptionCertificateNumber" TEXT,
  "taxExemptionCertificatePath" TEXT,
  "companyId" TEXT NOT NULL,
  "updatedAt" TIMESTAMP WITH TIME ZONE,
  "updatedBy" TEXT,

  CONSTRAINT "supplierTax_pkey" PRIMARY KEY ("supplierId"),
  CONSTRAINT "supplierTax_supplierId_fkey" FOREIGN KEY ("supplierId") REFERENCES "supplier"("id") ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "supplierTax_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "company"("id") ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "supplierTax_updatedBy_fkey" FOREIGN KEY ("updatedBy") REFERENCES "user"("id") ON UPDATE CASCADE ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS "supplierTax_supplierId_idx" ON "supplierTax"("supplierId");

ALTER TABLE "supplierTax" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "SELECT" ON "public"."supplierTax";
CREATE POLICY "SELECT" ON "public"."supplierTax"
FOR SELECT USING (
  "companyId" = ANY (
    (SELECT get_companies_with_employee_permission('purchasing_view'))::text[]
  )
);

DROP POLICY IF EXISTS "UPDATE" ON "public"."supplierTax";
CREATE POLICY "UPDATE" ON "public"."supplierTax"
FOR UPDATE USING (
  "companyId" = ANY (
    (SELECT get_companies_with_employee_permission('purchasing_update'))::text[]
  )
);

-- Backfill customerTax from existing customer records (only if source columns still exist)
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'customer' AND column_name = 'taxId'
  ) THEN
    INSERT INTO "customerTax" ("customerId", "taxId", "vatNumber", "eori", "companyId")
    SELECT c.id, c."taxId", c."vatNumber", c."eori", c."companyId"
    FROM "customer" c
    ON CONFLICT ("customerId") DO NOTHING;
  END IF;
END $$;

-- Backfill supplierTax from existing supplier records (only if source columns still exist)
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'supplier' AND column_name = 'taxId'
  ) THEN
    INSERT INTO "supplierTax" ("supplierId", "taxId", "vatNumber", "eori", "companyId")
    SELECT s.id, s."taxId", s."vatNumber", s."eori", s."companyId"
    FROM "supplier" s
    ON CONFLICT ("supplierId") DO NOTHING;
  END IF;
END $$;

-- Storage RLS for tax certificate uploads
DROP POLICY IF EXISTS "Employees with sales_create can upload tax certificates" ON storage.objects;
CREATE POLICY "Employees with sales_create can upload tax certificates" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'private'
    AND has_role('employee', (storage.foldername(name))[1])
    AND (has_company_permission('sales_create', (storage.foldername(name))[1]) OR has_company_permission('purchasing_create', (storage.foldername(name))[1]))
    AND (storage.foldername(name))[2] = 'tax-certificates'
  );

DROP POLICY IF EXISTS "Employees can view tax certificates" ON storage.objects;
CREATE POLICY "Employees can view tax certificates" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'private'
    AND has_role('employee', (storage.foldername(name))[1])
    AND (storage.foldername(name))[2] = 'tax-certificates'
  );

DROP POLICY IF EXISTS "Employees with sales_delete or purchasing_delete can delete tax certificates" ON storage.objects;
DROP POLICY IF EXISTS "Employees with sales_delete or purchasing_delete can delete tax" ON storage.objects;
CREATE POLICY "Employees with sales_delete or purchasing_delete can delete tax certificates" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'private'
    AND has_role('employee', (storage.foldername(name))[1])
    AND (has_company_permission('sales_delete', (storage.foldername(name))[1]) OR has_company_permission('purchasing_delete', (storage.foldername(name))[1]))
    AND (storage.foldername(name))[2] = 'tax-certificates'
  );

-- Update customer insert interceptor to also create customerTax
CREATE OR REPLACE FUNCTION sync_create_customer_entries(
  p_table TEXT,
  p_operation TEXT,
  p_new JSONB,
  p_old JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF p_operation != 'INSERT' THEN RETURN; END IF;

  INSERT INTO "customerPayment"("customerId", "invoiceCustomerId", "companyId")
  VALUES (p_new->>'id', p_new->>'id', p_new->>'companyId');

  INSERT INTO "customerShipping"("customerId", "shippingCustomerId", "companyId")
  VALUES (p_new->>'id', p_new->>'id', p_new->>'companyId');

  INSERT INTO "customerTax"("customerId", "companyId")
  VALUES (p_new->>'id', p_new->>'companyId');
END;
$$;

-- Update supplier insert interceptor to also create supplierTax
CREATE OR REPLACE FUNCTION sync_create_supplier_entries(
  p_table TEXT,
  p_operation TEXT,
  p_new JSONB,
  p_old JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF p_operation != 'INSERT' THEN RETURN; END IF;

  INSERT INTO "supplierPayment"("supplierId", "invoiceSupplierId", "companyId")
  VALUES (p_new->>'id', p_new->>'id', p_new->>'companyId');

  INSERT INTO "supplierShipping"("supplierId", "shippingSupplierId", "companyId")
  VALUES (p_new->>'id', p_new->>'id', p_new->>'companyId');

  INSERT INTO "supplierTax"("supplierId", "companyId")
  VALUES (p_new->>'id', p_new->>'companyId');
END;
$$;

-- Drop views that depend on the columns we're removing
DROP VIEW IF EXISTS "suppliers";
DROP VIEW IF EXISTS "customers";
DROP VIEW IF EXISTS "purchaseOrderLocations";
DROP VIEW IF EXISTS "salesOrderLocations";
DROP VIEW IF EXISTS "salesInvoiceLocations";
DROP VIEW IF EXISTS "quoteCustomerDetails";

-- Remove taxId, vatNumber, and eori from customer and supplier tables
ALTER TABLE "customer" DROP COLUMN IF EXISTS "taxId";
ALTER TABLE "customer" DROP COLUMN IF EXISTS "vatNumber";
ALTER TABLE "customer" DROP COLUMN IF EXISTS "eori";
ALTER TABLE "supplier" DROP COLUMN IF EXISTS "taxId";
ALTER TABLE "supplier" DROP COLUMN IF EXISTS "vatNumber";
ALTER TABLE "supplier" DROP COLUMN IF EXISTS "eori";

-- Recreate suppliers view (join taxId/vatNumber from supplierTax)
CREATE OR REPLACE VIEW "suppliers" WITH(SECURITY_INVOKER=true) AS
  SELECT
    s.id,
    s.name,
    s."supplierTypeId",
    s."supplierStatus" as "status",
    stx."taxId",
    s."accountManagerId",
    s.logo,
    s.assignee,
    s."companyId",
    s."createdAt",
    s."createdBy",
    s."updatedAt",
    s."updatedBy",
    s."customFields",
    s."currencyCode",
    stx."vatNumber",
    stx."eori",
    s.website,
    (
      SELECT COALESCE(
        jsonb_object_agg(
          eim."integration",
          CASE
            WHEN eim."metadata" IS NOT NULL THEN eim."metadata"
            ELSE to_jsonb(eim."externalId")
          END
        ) FILTER (WHERE eim."externalId" IS NOT NULL OR eim."metadata" IS NOT NULL),
        '{}'::jsonb
      )
      FROM "externalIntegrationMapping" eim
      WHERE eim."entityType" = 'supplier' AND eim."entityId" = s.id
    ) AS "externalId",
    s.tags,
    s."taxPercent",
    s."purchasingContactId",
    s.embedding,
    s."defaultCc",
    st.name AS "type",
    po.count AS "orderCount",
    p.count AS "partCount",
    pc."workPhone" AS "phone",
    pc.fax AS "fax"
  FROM "supplier" s
  LEFT JOIN "supplierTax" stx ON stx."supplierId" = s.id
  LEFT JOIN "supplierType" st ON st.id = s."supplierTypeId"
  LEFT JOIN (
    SELECT
      "supplierId",
      COUNT(*) AS "count"
    FROM "purchaseOrder"
    GROUP BY "supplierId"
  ) po ON po."supplierId" = s.id
  LEFT JOIN (
    SELECT
      "supplierId",
      COUNT(*) AS "count"
    FROM "supplierPart"
    GROUP BY "supplierId"
  ) p ON p."supplierId" = s.id
  LEFT JOIN (
    SELECT DISTINCT ON (sc."supplierId")
      sc."supplierId" AS id,
      co."workPhone",
      co."fax"
    FROM "supplierContact" sc
    JOIN "contact" co
      ON co.id = sc."contactId"
    ORDER BY sc."supplierId", sc.id
  ) pc
    ON pc.id = s.id;

-- Recreate customers view (join taxId/vatNumber from customerTax)
CREATE OR REPLACE VIEW "customers" WITH(SECURITY_INVOKER=true) AS
  SELECT
    c.id,
    c.name,
    c."customerTypeId",
    c."customerStatusId",
    ctx."taxId",
    c."accountManagerId",
    c.logo,
    c.assignee,
    c."taxPercent",
    c."tags",
    c.website,
    c."companyId",
    c."createdAt",
    c."createdBy",
    c."updatedAt",
    c."updatedBy",
    c."customFields",
    c."currencyCode",
    c."salesContactId",
    c."defaultCc",
    ctx."vatNumber",
    ctx."eori",
    (
      SELECT COALESCE(
        jsonb_object_agg(
          eim."integration",
          CASE
            WHEN eim."metadata" IS NOT NULL THEN eim."metadata"
            ELSE to_jsonb(eim."externalId")
          END
        ) FILTER (WHERE eim."externalId" IS NOT NULL OR eim."metadata" IS NOT NULL),
        '{}'::jsonb
      )
      FROM "externalIntegrationMapping" eim
      WHERE eim."entityType" = 'customer' AND eim."entityId" = c.id
    ) AS "externalId",
    ct.name AS "type",
    cs.name AS "status",
    so.count AS "orderCount",
    pc."workPhone" AS "phone",
    pc."fax" AS "fax"
  FROM "customer" c
  LEFT JOIN "customerTax" ctx ON ctx."customerId" = c.id
  LEFT JOIN "customerType" ct ON ct.id = c."customerTypeId"
  LEFT JOIN "customerStatus" cs ON cs.id = c."customerStatusId"
  LEFT JOIN (
    SELECT
      "customerId",
      COUNT(*) AS "count"
    FROM "salesOrder"
    GROUP BY "customerId"
  ) so ON so."customerId" = c.id
  LEFT JOIN (
    SELECT DISTINCT ON (cc."customerId")
      cc."customerId",
      co."workPhone",
      co."fax"
    FROM "customerContact" cc
    INNER JOIN "contact" co ON co.id = cc."contactId"
    ORDER BY cc."customerId"
  ) pc ON pc."customerId" = c.id;

-- Recreate purchaseOrderLocations view (join taxId/vatNumber from supplierTax)
CREATE OR REPLACE VIEW "purchaseOrderLocations" WITH(SECURITY_INVOKER=true) AS
  SELECT
    po.id,
    s.name AS "supplierName",
    sa."addressLine1" AS "supplierAddressLine1",
    sa."addressLine2" AS "supplierAddressLine2",
    sa."city" AS "supplierCity",
    sa."stateProvince" AS "supplierStateProvince",
    sa."postalCode" AS "supplierPostalCode",
    sa."countryCode" AS "supplierCountryCode",
    sc."name" AS "supplierCountryName",
    stx."taxId" AS "supplierTaxId",
    stx."vatNumber" AS "supplierVatNumber",
    stx."eori" AS "supplierEori",
    scon."fullName" AS "supplierContactName",
    scon."email" AS "supplierContactEmail",
    comp."countryCode" AS "companyCountryCode",
    compc."name" AS "companyCountryName",
    dl.name AS "deliveryName",
    dl."addressLine1" AS "deliveryAddressLine1",
    dl."addressLine2" AS "deliveryAddressLine2",
    dl."city" AS "deliveryCity",
    dl."stateProvince" AS "deliveryStateProvince",
    dl."postalCode" AS "deliveryPostalCode",
    dl."countryCode" AS "deliveryCountryCode",
    dc."name" AS "deliveryCountryName",
    pod."dropShipment",
    c.name AS "customerName",
    ca."addressLine1" AS "customerAddressLine1",
    ca."addressLine2" AS "customerAddressLine2",
    ca."city" AS "customerCity",
    ca."stateProvince" AS "customerStateProvince",
    ca."postalCode" AS "customerPostalCode",
    ca."countryCode" AS "customerCountryCode",
    cc."name" AS "customerCountryName"
  FROM "purchaseOrder" po
  LEFT OUTER JOIN "supplier" s
    ON s.id = po."supplierId"
  LEFT OUTER JOIN "supplierTax" stx
    ON stx."supplierId" = s.id
  LEFT OUTER JOIN "supplierLocation" sl
    ON sl.id = po."supplierLocationId"
  LEFT OUTER JOIN "address" sa
    ON sa.id = sl."addressId"
  LEFT OUTER JOIN "country" sc
    ON sc.alpha2 = sa."countryCode"
  LEFT OUTER JOIN "supplierContact" sct
    ON sct.id = po."supplierContactId"
  LEFT OUTER JOIN "contact" scon
    ON scon.id = sct."contactId"
  LEFT OUTER JOIN "company" comp
    ON comp.id = po."companyId"
  LEFT OUTER JOIN "country" compc
    ON compc.alpha2 = comp."countryCode"
  INNER JOIN "purchaseOrderDelivery" pod
    ON pod.id = po.id
  LEFT OUTER JOIN "location" dl
    ON dl.id = pod."locationId"
  LEFT OUTER JOIN "country" dc
    ON dc.alpha2 = dl."countryCode"
  LEFT OUTER JOIN "customer" c
    ON c.id = pod."customerId"
  LEFT OUTER JOIN "customerLocation" cl
    ON cl.id = pod."customerLocationId"
  LEFT OUTER JOIN "address" ca
    ON ca.id = cl."addressId"
  LEFT OUTER JOIN "country" cc
    ON cc.alpha2 = ca."countryCode";

CREATE OR REPLACE VIEW "salesOrderLocations" WITH(SECURITY_INVOKER=true) AS
  SELECT
    so.id,
    c.name AS "customerName",
    ca."addressLine1" AS "customerAddressLine1",
    ca."addressLine2" AS "customerAddressLine2",
    ca."city" AS "customerCity",
    ca."stateProvince" AS "customerStateProvince",
    ca."postalCode" AS "customerPostalCode",
    ca."countryCode" AS "customerCountryCode",
    cc."name" AS "customerCountryName",
    ctx."taxId" AS "customerTaxId",
    ctx."vatNumber" AS "customerVatNumber",
    ctx."eori" AS "customerEori",
    pc.name AS "paymentCustomerName",
    pa."addressLine1" AS "paymentAddressLine1",
    pa."addressLine2" AS "paymentAddressLine2",
    pa."city" AS "paymentCity",
    pa."stateProvince" AS "paymentStateProvince",
    pa."postalCode" AS "paymentPostalCode",
    pa."countryCode" AS "paymentCountryCode",
    pn."name" AS "paymentCountryName"
  FROM "salesOrder" so
  INNER JOIN "customer" c
    ON c.id = so."customerId"
  LEFT OUTER JOIN "customerTax" ctx
    ON ctx."customerId" = c.id
  LEFT OUTER JOIN "customerLocation" cl
    ON cl.id = so."customerLocationId"
  LEFT OUTER JOIN "address" ca
    ON ca.id = cl."addressId"
  LEFT OUTER JOIN "country" cc
    ON cc.alpha2 = ca."countryCode"
  LEFT OUTER JOIN "salesOrderPayment" sop
    ON sop.id = so.id
  LEFT OUTER JOIN "customer" pc
    ON pc.id = sop."invoiceCustomerId"
  LEFT OUTER JOIN "customerLocation" pl
    ON pl.id = sop."invoiceCustomerLocationId"
  LEFT OUTER JOIN "address" pa
    ON pa.id = pl."addressId"
  LEFT OUTER JOIN "country" pn
    ON pn.alpha2 = pa."countryCode";

CREATE OR REPLACE VIEW "salesInvoiceLocations" WITH(SECURITY_INVOKER=true) AS
  SELECT
    si.id,
    c.name AS "customerName",
    ca."addressLine1" AS "customerAddressLine1",
    ca."addressLine2" AS "customerAddressLine2",
    ca."city" AS "customerCity",
    ca."stateProvince" AS "customerStateProvince",
    ca."postalCode" AS "customerPostalCode",
    ca."countryCode" AS "customerCountryCode",
    cc."name" AS "customerCountryName",
    ctx."taxId" AS "customerTaxId",
    ctx."vatNumber" AS "customerVatNumber",
    ctx."eori" AS "customerEori",
    ic.name AS "invoiceCustomerName",
    ica."addressLine1" AS "invoiceAddressLine1",
    ica."addressLine2" AS "invoiceAddressLine2",
    ica."city" AS "invoiceCity",
    ica."stateProvince" AS "invoiceStateProvince",
    ica."postalCode" AS "invoicePostalCode",
    ica."countryCode" AS "invoiceCountryCode",
    icc."name" AS "invoiceCountryName",
    sc.name AS "shipmentCustomerName",
    sa."addressLine1" AS "shipmentAddressLine1",
    sa."addressLine2" AS "shipmentAddressLine2",
    sa."city" AS "shipmentCity",
    sa."stateProvince" AS "shipmentStateProvince",
    sa."postalCode" AS "shipmentPostalCode",
    sa."countryCode" AS "shipmentCountryCode",
    scc."name" AS "shipmentCountryName"
  FROM "salesInvoice" si
  INNER JOIN "customer" c
    ON c.id = si."customerId"
  LEFT OUTER JOIN "customerTax" ctx
    ON ctx."customerId" = c.id
  LEFT OUTER JOIN "customerLocation" cl
    ON cl.id = si."locationId"
  LEFT OUTER JOIN "address" ca
    ON ca.id = cl."addressId"
  LEFT OUTER JOIN "country" cc
    ON cc.alpha2 = ca."countryCode"
  LEFT OUTER JOIN "customer" ic
    ON ic.id = si."invoiceCustomerId"
  LEFT OUTER JOIN "customerLocation" icl
    ON icl.id = si."invoiceCustomerLocationId"
  LEFT OUTER JOIN "address" ica
    ON ica.id = icl."addressId"
  LEFT OUTER JOIN "country" icc
    ON icc.alpha2 = ica."countryCode"
  LEFT OUTER JOIN "salesInvoiceShipment" sis
    ON sis.id = si.id
  LEFT OUTER JOIN "customerLocation" scl
    ON scl.id = sis."locationId"
  LEFT OUTER JOIN "address" sa
    ON sa.id = scl."addressId"
  LEFT OUTER JOIN "country" scc
    ON scc.alpha2 = sa."countryCode"
  LEFT OUTER JOIN "customer" sc
    ON sc.id = scl."customerId";

CREATE OR REPLACE VIEW "quoteCustomerDetails" WITH(SECURITY_INVOKER=true) AS
SELECT
  q.id as "quoteId",
  c.name as "customerName",
  contact."fullName" as "contactName",
  contact."email" as "contactEmail",
  ca."addressLine1" AS "customerAddressLine1",
  ca."addressLine2" AS "customerAddressLine2",
  ca."city" AS "customerCity",
  ca."stateProvince" AS "customerStateProvince",
  ca."postalCode" AS "customerPostalCode",
  ca."countryCode" AS "customerCountryCode",
  country."name" AS "customerCountryName",
  ctx."taxId" AS "customerTaxId",
  ctx."vatNumber" AS "customerVatNumber",
  ctx."eori" AS "customerEori"
FROM "quote" q
INNER JOIN "customer" c ON c."id" = q."customerId"
LEFT JOIN "customerTax" ctx ON ctx."customerId" = c.id
LEFT JOIN "customerContact" cc ON cc."id" = q."customerContactId"
LEFT JOIN "contact" contact ON contact.id = cc."contactId"
LEFT JOIN "customerLocation" cl ON cl."id" = q."customerLocationId"
LEFT JOIN "address" ca ON ca."id" = cl."addressId"
LEFT OUTER JOIN "country" country ON country.alpha2 = ca."countryCode";

-- Update search index functions to look up taxId from tax tables
CREATE OR REPLACE FUNCTION sync_customer_to_search_index()
RETURNS TRIGGER AS $$
DECLARE
  v_table_name TEXT;
  v_cust_type TEXT;
  v_cust_status TEXT;
  v_tax_id TEXT;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_table_name := 'searchIndex_' || OLD."companyId";
    EXECUTE format('DELETE FROM %I WHERE "entityType" = $1 AND "entityId" = $2', v_table_name)
      USING 'customer', OLD.id;
    RETURN OLD;
  END IF;

  v_table_name := 'searchIndex_' || NEW."companyId";

  SELECT name INTO v_cust_type FROM "customerType" WHERE id = NEW."customerTypeId";
  SELECT name INTO v_cust_status FROM "customerStatus" WHERE id = NEW."customerStatusId";
  SELECT "taxId" INTO v_tax_id FROM "customerTax" WHERE "customerId" = NEW.id;

  EXECUTE format('
    INSERT INTO %I ("entityType", "entityId", "title", "link", "tags", "metadata", "searchVector")
    VALUES ($1, $2, $3, $4, $5, $6, to_tsvector(''english'', $3 || '' '' || COALESCE(array_to_string($5, '' ''), '''')))
    ON CONFLICT ("entityType", "entityId") DO UPDATE SET
      "title" = EXCLUDED."title",
      "tags" = EXCLUDED."tags",
      "metadata" = EXCLUDED."metadata",
      "searchVector" = to_tsvector(''english'', EXCLUDED."title" || '' '' || COALESCE(array_to_string(EXCLUDED."tags", '' ''), '''')),
      "updatedAt" = NOW()
  ', v_table_name) USING
    'customer',
    NEW.id,
    NEW.name,
    '/x/customer/' || NEW.id,
    ARRAY_REMOVE(ARRAY[v_cust_type, v_cust_status], NULL),
    jsonb_build_object('taxId', v_tax_id);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION sync_supplier_to_search_index()
RETURNS TRIGGER AS $$
DECLARE
  v_table_name TEXT;
  v_supp_type TEXT;
  v_supp_status TEXT;
  v_tax_id TEXT;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_table_name := 'searchIndex_' || OLD."companyId";
    EXECUTE format('DELETE FROM %I WHERE "entityType" = $1 AND "entityId" = $2', v_table_name)
      USING 'supplier', OLD.id;
    RETURN OLD;
  END IF;

  v_table_name := 'searchIndex_' || NEW."companyId";

  SELECT name INTO v_supp_type FROM "supplierType" WHERE id = NEW."supplierTypeId";
  v_supp_status := NEW."supplierStatus"::TEXT;
  SELECT "taxId" INTO v_tax_id FROM "supplierTax" WHERE "supplierId" = NEW.id;

  EXECUTE format('
    INSERT INTO %I ("entityType", "entityId", "title", "link", "tags", "metadata", "searchVector")
    VALUES ($1, $2, $3, $4, $5, $6, to_tsvector(''english'', $3 || '' '' || COALESCE(array_to_string($5, '' ''), '''')))
    ON CONFLICT ("entityType", "entityId") DO UPDATE SET
      "title" = EXCLUDED."title",
      "tags" = EXCLUDED."tags",
      "metadata" = EXCLUDED."metadata",
      "searchVector" = to_tsvector(''english'', EXCLUDED."title" || '' '' || COALESCE(array_to_string(EXCLUDED."tags", '' ''), '''')),
      "updatedAt" = NOW()
  ', v_table_name) USING
    'supplier',
    NEW.id,
    NEW.name,
    '/x/supplier/' || NEW.id,
    ARRAY_REMOVE(ARRAY[v_supp_type, v_supp_status], NULL),
    jsonb_build_object('taxId', v_tax_id);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update populate_company_search_index to join tax tables
CREATE OR REPLACE FUNCTION populate_company_search_index(p_company_id TEXT)
RETURNS VOID AS $$
DECLARE
  v_table_name TEXT := 'searchIndex_' || p_company_id;
BEGIN
  -- Populate employees
  EXECUTE format('
    INSERT INTO %I ("entityType", "entityId", "title", "link", "tags", "metadata", "searchVector")
    SELECT
      ''employee'',
      e.id,
      COALESCE(u."fullName", ''''),
      ''/x/person/'' || e.id,
      ARRAY_REMOVE(ARRAY[et.name], NULL),
      jsonb_build_object(''active'', e.active),
      to_tsvector(''english'', COALESCE(u."fullName", '''') || '' '' || COALESCE(array_to_string(ARRAY_REMOVE(ARRAY[et.name], NULL), '' ''), ''''))
    FROM "employee" e
    INNER JOIN "user" u ON u.id = e.id
    LEFT JOIN "employeeType" et ON et.id = e."employeeTypeId"
    WHERE e."companyId" = $1 AND e.active = true
    ON CONFLICT ("entityType", "entityId") DO UPDATE SET
      "title" = EXCLUDED."title",
      "tags" = EXCLUDED."tags",
      "metadata" = EXCLUDED."metadata",
      "searchVector" = EXCLUDED."searchVector",
      "updatedAt" = NOW()
  ', v_table_name) USING p_company_id;

  -- Populate customers (join customerTax for taxId)
  EXECUTE format('
    INSERT INTO %I ("entityType", "entityId", "title", "link", "tags", "metadata", "searchVector")
    SELECT
      ''customer'',
      c.id,
      c.name,
      ''/x/customer/'' || c.id,
      ARRAY_REMOVE(ARRAY[ct.name, cs.name], NULL),
      jsonb_build_object(''taxId'', ctx."taxId"),
      to_tsvector(''english'', c.name || '' '' || COALESCE(array_to_string(ARRAY_REMOVE(ARRAY[ct.name, cs.name], NULL), '' ''), ''''))
    FROM "customer" c
    LEFT JOIN "customerTax" ctx ON ctx."customerId" = c.id
    LEFT JOIN "customerType" ct ON ct.id = c."customerTypeId"
    LEFT JOIN "customerStatus" cs ON cs.id = c."customerStatusId"
    WHERE c."companyId" = $1
    ON CONFLICT ("entityType", "entityId") DO UPDATE SET
      "title" = EXCLUDED."title",
      "tags" = EXCLUDED."tags",
      "metadata" = EXCLUDED."metadata",
      "searchVector" = EXCLUDED."searchVector",
      "updatedAt" = NOW()
  ', v_table_name) USING p_company_id;

  -- Populate suppliers (join supplierTax for taxId)
  EXECUTE format('
    INSERT INTO %I ("entityType", "entityId", "title", "link", "tags", "metadata", "searchVector")
    SELECT
      ''supplier'',
      s.id,
      s.name,
      ''/x/supplier/'' || s.id,
      ARRAY_REMOVE(ARRAY[st.name, s."supplierStatus"::TEXT], NULL),
      jsonb_build_object(''taxId'', stx."taxId"),
      to_tsvector(''english'', s.name || '' '' || COALESCE(array_to_string(ARRAY_REMOVE(ARRAY[st.name, s."supplierStatus"::TEXT], NULL), '' ''), ''''))
    FROM "supplier" s
    LEFT JOIN "supplierTax" stx ON stx."supplierId" = s.id
    LEFT JOIN "supplierType" st ON st.id = s."supplierTypeId"
    WHERE s."companyId" = $1
    ON CONFLICT ("entityType", "entityId") DO UPDATE SET
      "title" = EXCLUDED."title",
      "tags" = EXCLUDED."tags",
      "metadata" = EXCLUDED."metadata",
      "searchVector" = EXCLUDED."searchVector",
      "updatedAt" = NOW()
  ', v_table_name) USING p_company_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach audit event triggers
SELECT attach_event_trigger('customerTax', ARRAY[]::TEXT[], ARRAY[]::TEXT[]);
SELECT attach_event_trigger('supplierTax', ARRAY[]::TEXT[], ARRAY[]::TEXT[]);
