-- Company Groups: infrastructure for multi-entity, multi-currency accounting.
-- A company group is a collection of companies sharing financial infrastructure
-- (chart of accounts, dimensions, currencies). Each company maintains its own
-- operational data (journals, orders, invoices).

-- =====================================================
-- PART 1: Company Group Infrastructure
-- =====================================================

CREATE TABLE "companyGroup" (
  "id" TEXT NOT NULL DEFAULT id('cg'),
  "name" TEXT NOT NULL,
  "createdBy" TEXT,
  "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  "updatedBy" TEXT,
  "updatedAt" TIMESTAMP WITH TIME ZONE,

  CONSTRAINT "companyGroup_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "companyGroup_createdBy_fkey" FOREIGN KEY ("createdBy") REFERENCES "user"("id"),
  CONSTRAINT "companyGroup_updatedBy_fkey" FOREIGN KEY ("updatedBy") REFERENCES "user"("id")
);

-- Service role only — no user-level RLS policies
ALTER TABLE "companyGroup" ENABLE ROW LEVEL SECURITY;

-- Add company group and hierarchy columns to company table
ALTER TABLE "company" ADD COLUMN "companyGroupId" TEXT;
ALTER TABLE "company" ADD COLUMN "parentCompanyId" TEXT;
ALTER TABLE "company" ADD COLUMN "isEliminationEntity" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "company" ADD COLUMN "active" BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE "company"
  ADD CONSTRAINT "company_companyGroupId_fkey"
  FOREIGN KEY ("companyGroupId") REFERENCES "companyGroup"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "company"
  ADD CONSTRAINT "company_parentCompanyId_fkey"
  FOREIGN KEY ("parentCompanyId") REFERENCES "company"("id") ON DELETE SET NULL ON UPDATE CASCADE;

CREATE INDEX "company_companyGroupId_idx" ON "company"("companyGroupId");
CREATE INDEX "company_parentCompanyId_idx" ON "company"("parentCompanyId");

-- Backfill: create a companyGroup for each existing company
DO $$
DECLARE
  comp RECORD;
  new_group_id TEXT;
BEGIN
  FOR comp IN SELECT "id", "name" FROM "company" LOOP
    INSERT INTO "companyGroup" ("name")
    VALUES (comp."name")
    RETURNING "id" INTO new_group_id;

    UPDATE "company" SET "companyGroupId" = new_group_id WHERE "id" = comp."id";
  END LOOP;
END;
$$;

-- =====================================================
-- PART 2: RLS Helper Functions
-- =====================================================

-- Returns companyGroup IDs where the user is an employee
-- in at least one member company. Used for SELECT policies
-- on group-scoped tables.
CREATE OR REPLACE FUNCTION get_company_groups_for_employee()
RETURNS text[]
LANGUAGE "plpgsql" SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  employee_companies text[];
  group_ids text[];
  api_key_company text;
BEGIN
  api_key_company := get_company_id_from_api_key();

  IF api_key_company IS NOT NULL THEN
    SELECT ARRAY["companyGroupId"::text]
    INTO group_ids
    FROM "company"
    WHERE "id" = api_key_company
      AND "companyGroupId" IS NOT NULL;
    RETURN COALESCE(group_ids, '{}');
  END IF;

  SELECT array_agg("companyId"::text)
  INTO employee_companies
  FROM "userToCompany"
  WHERE "userId" = auth.uid()::text AND "role" = 'employee';

  IF employee_companies IS NULL THEN
    RETURN '{}';
  END IF;

  SELECT array_agg(DISTINCT "companyGroupId"::text)
  INTO group_ids
  FROM "company"
  WHERE "id" = ANY(employee_companies)
    AND "companyGroupId" IS NOT NULL;

  RETURN COALESCE(group_ids, '{}');
END;
$$;

-- Returns companyGroup IDs where the user has the given
-- permission on the root company (parentCompanyId IS NULL).
-- Used for INSERT/UPDATE/DELETE policies on group-scoped tables.
CREATE OR REPLACE FUNCTION get_company_groups_for_root_permission(permission text)
RETURNS text[]
LANGUAGE "plpgsql" SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  permitted_companies text[];
  group_ids text[];
BEGIN
  permitted_companies := get_companies_with_employee_permission(permission);

  IF permitted_companies IS NULL OR array_length(permitted_companies, 1) IS NULL THEN
    RETURN '{}';
  END IF;

  -- Only consider root companies (no parent)
  SELECT array_agg(DISTINCT "companyGroupId"::text)
  INTO group_ids
  FROM "company"
  WHERE "id" = ANY(permitted_companies)
    AND "parentCompanyId" IS NULL
    AND "companyGroupId" IS NOT NULL;

  RETURN COALESCE(group_ids, '{}');
END;
$$;

-- =====================================================
-- PART 3: Drop Dependent Objects
-- =====================================================

-- 3a. Drop views
DROP VIEW IF EXISTS "accounts";
DROP VIEW IF EXISTS "accountCategories";
DROP VIEW IF EXISTS "currencies";

-- 3b. Drop composite FKs from operational tables → account

-- accountDefault (38 account FKs)
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_salesAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_salesDiscountAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_costOfGoodsSoldAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_purchaseAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_directCostAppliedAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_overheadCostAppliedAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_purchaseVarianceAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_inventoryAdjustmentVarianceAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_materialVarianceAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_capacityVarianceAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_overheadAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_maintenanceAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_assetDepreciationExpenseAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_assetGainsAndLossesAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_serviceChargeAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_interestAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_supplierPaymentDiscountAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_customerPaymentDiscountAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_roundingAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_aquisitionCostAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_aquisitionCostOnDisposalAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_accumulatedDepreciationAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_accumulatedDepreciationOnDisposalAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_inventoryAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_inventoryInterimAccrualAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_workInProgressAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_receivablesAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_inventoryShippedNotInvoicedAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_bankCashAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_bankLocalCurrencyAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_bankForeignCurrencyAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_prepaymentAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_payablesAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_inventoryReceivedNotInvoicedAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_salesTaxPayableAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_reverseChargeSalesTaxPayableAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_purchaseTaxPayableAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_retainedEarningsAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_inventoryInvoicedNotReceivedAccount_fkey";

-- postingGroupInventory (tables dropped in next migration, but FKs block account_number_key drop)
ALTER TABLE "postingGroupInventory" DROP CONSTRAINT IF EXISTS "postingGroupInventory_costOfGoodsSoldAccount_fkey";
ALTER TABLE "postingGroupInventory" DROP CONSTRAINT IF EXISTS "postingGroupInventory_inventoryAccount_fkey";
ALTER TABLE "postingGroupInventory" DROP CONSTRAINT IF EXISTS "postingGroupInventory_inventoryInterimAccrualAccount_fkey";
ALTER TABLE "postingGroupInventory" DROP CONSTRAINT IF EXISTS "postingGroupInventory_inventoryReceivedNotInvoicedAccount_fkey";
ALTER TABLE "postingGroupInventory" DROP CONSTRAINT IF EXISTS "postingGroupInventory_inventoryInvoicedNotReceivedAccount_fkey";
ALTER TABLE "postingGroupInventory" DROP CONSTRAINT IF EXISTS "postingGroupInventory_inventoryShippedNotInvoicedAccount_fkey";
ALTER TABLE "postingGroupInventory" DROP CONSTRAINT IF EXISTS "postingGroupInventory_workInProgressAccount_fkey";
ALTER TABLE "postingGroupInventory" DROP CONSTRAINT IF EXISTS "postingGroupInventory_directCostAppliedAccount_fkey";
ALTER TABLE "postingGroupInventory" DROP CONSTRAINT IF EXISTS "postingGroupInventory_overheadCostAppliedAccount_fkey";
ALTER TABLE "postingGroupInventory" DROP CONSTRAINT IF EXISTS "postingGroupInventory_purchaseVarianceAccount_fkey";
ALTER TABLE "postingGroupInventory" DROP CONSTRAINT IF EXISTS "postingGroupInventory_inventoryAdjustmentVarianceAccount_fkey";
ALTER TABLE "postingGroupInventory" DROP CONSTRAINT IF EXISTS "postingGroupInventory_materialVarianceAccount_fkey";
ALTER TABLE "postingGroupInventory" DROP CONSTRAINT IF EXISTS "postingGroupInventory_capacityVarianceAccount_fkey";
ALTER TABLE "postingGroupInventory" DROP CONSTRAINT IF EXISTS "postingGroupInventory_overheadAccount_fkey";

-- postingGroupPurchasing
ALTER TABLE "postingGroupPurchasing" DROP CONSTRAINT IF EXISTS "postingGroupPurchasing_payablesAccount_fkey";
ALTER TABLE "postingGroupPurchasing" DROP CONSTRAINT IF EXISTS "postingGroupPurchasing_purchaseAccount_fkey";
ALTER TABLE "postingGroupPurchasing" DROP CONSTRAINT IF EXISTS "postingGroupPurchasing_purchaseDiscountAccount_fkey";
ALTER TABLE "postingGroupPurchasing" DROP CONSTRAINT IF EXISTS "postingGroupPurchasing_purchaseCreditAccount_fkey";
ALTER TABLE "postingGroupPurchasing" DROP CONSTRAINT IF EXISTS "postingGroupPurchasing_purchasePrepaymentAccount_fkey";
ALTER TABLE "postingGroupPurchasing" DROP CONSTRAINT IF EXISTS "postingGroupPurchasing_purchaseTaxPayableAccount_fkey";

-- postingGroupSales
ALTER TABLE "postingGroupSales" DROP CONSTRAINT IF EXISTS "postingGroupSales_receivablesAccount_fkey";
ALTER TABLE "postingGroupSales" DROP CONSTRAINT IF EXISTS "postingGroupSales_salesAccount_fkey";
ALTER TABLE "postingGroupSales" DROP CONSTRAINT IF EXISTS "postingGroupSales_salesDiscountAccount_fkey";
ALTER TABLE "postingGroupSales" DROP CONSTRAINT IF EXISTS "postingGroupSales_salesCreditAccount_fkey";
ALTER TABLE "postingGroupSales" DROP CONSTRAINT IF EXISTS "postingGroupSales_salesPrepaymentAccount_fkey";
ALTER TABLE "postingGroupSales" DROP CONSTRAINT IF EXISTS "postingGroupSales_salesTaxPayableAccount_fkey";

-- journalLine
ALTER TABLE "journalLine" DROP CONSTRAINT IF EXISTS "journalLine_accountNumber_fkey";

-- purchaseOrderLine
ALTER TABLE "purchaseOrderLine" DROP CONSTRAINT IF EXISTS "purchaseOrderLine_accountNumber_fkey";

-- salesOrderLine
ALTER TABLE "salesOrderLine" DROP CONSTRAINT IF EXISTS "salesOrderLine_accountNumber_fkey";

-- salesInvoiceLine
ALTER TABLE "salesInvoiceLine" DROP CONSTRAINT IF EXISTS "salesInvoiceLine_accountNumber_fkey";

-- purchaseInvoiceLine (note: table is singular, constraint names are plural)
ALTER TABLE "purchaseInvoiceLine" DROP CONSTRAINT IF EXISTS "purchaseInvoiceLines_accountNumber_fkey";

-- shippingMethod
ALTER TABLE "shippingMethod" DROP CONSTRAINT IF EXISTS "shippingMethod_carrierAccountId_fkey";

-- 3c. Drop composite FKs from operational tables → currency
ALTER TABLE "purchaseInvoice" DROP CONSTRAINT IF EXISTS "purchaseInvoice_currencyCode_fkey";
ALTER TABLE "purchaseInvoiceLine" DROP CONSTRAINT IF EXISTS "purchaseInvoiceLines_currencyCode_fkey";
ALTER TABLE "purchasePayment" DROP CONSTRAINT IF EXISTS "purchasePayment_currencyCode_fkey";
ALTER TABLE "purchaseOrderPayment" DROP CONSTRAINT IF EXISTS "purchaseOrderPayment_currencyCode_fkey";
ALTER TABLE "salesOrder" DROP CONSTRAINT IF EXISTS "salesOrder_currencyCode_fkey";
ALTER TABLE "salesOrderPayment" DROP CONSTRAINT IF EXISTS "salesOrderPayment_currencyCode_fkey";
ALTER TABLE "itemUnitSalePrice" DROP CONSTRAINT IF EXISTS "itemUnitSalePrice_currencyCode_fkey";
ALTER TABLE "supplierPayment" DROP CONSTRAINT IF EXISTS "supplierPayment_currencyCode_fkey";
ALTER TABLE "customerPayment" DROP CONSTRAINT IF EXISTS "customerPayment_currencyCode_fkey";
ALTER TABLE "quotePayment" DROP CONSTRAINT IF EXISTS "quotePayment_currencyCode_fkey";

-- 3d. Drop old RLS policies on shared tables
DROP POLICY IF EXISTS "SELECT" ON "public"."account";
DROP POLICY IF EXISTS "INSERT" ON "public"."account";
DROP POLICY IF EXISTS "UPDATE" ON "public"."account";
DROP POLICY IF EXISTS "DELETE" ON "public"."account";

DROP POLICY IF EXISTS "SELECT" ON "public"."accountCategory";
DROP POLICY IF EXISTS "INSERT" ON "public"."accountCategory";
DROP POLICY IF EXISTS "UPDATE" ON "public"."accountCategory";
DROP POLICY IF EXISTS "DELETE" ON "public"."accountCategory";

DROP POLICY IF EXISTS "SELECT" ON "public"."accountSubcategory";
DROP POLICY IF EXISTS "INSERT" ON "public"."accountSubcategory";
DROP POLICY IF EXISTS "UPDATE" ON "public"."accountSubcategory";
DROP POLICY IF EXISTS "DELETE" ON "public"."accountSubcategory";

DROP POLICY IF EXISTS "SELECT" ON "public"."currency";
DROP POLICY IF EXISTS "UPDATE" ON "public"."currency";
DROP POLICY IF EXISTS "Employees with accounting_create can insert currencies" ON "public"."currency";
DROP POLICY IF EXISTS "Employees with accounting_delete can delete currencies" ON "public"."currency";

-- =====================================================
-- PART 4: Migrate Shared Tables
-- =====================================================

-- 4a. account: companyId → companyGroupId

ALTER TABLE "account" ADD COLUMN "companyGroupId" TEXT;
UPDATE "account" SET "companyGroupId" = c."companyGroupId"
  FROM "company" c WHERE c."id" = "account"."companyId";
ALTER TABLE "account" ALTER COLUMN "companyGroupId" SET NOT NULL;

ALTER TABLE "account" DROP CONSTRAINT IF EXISTS "account_number_key";
ALTER TABLE "account" DROP CONSTRAINT IF EXISTS "account_name_key";
ALTER TABLE "account" DROP CONSTRAINT IF EXISTS "account_companyId_fkey";
DROP INDEX IF EXISTS "account_number_idx";
DROP INDEX IF EXISTS "account_type_idx";
DROP INDEX IF EXISTS "account_incomeBalance_idx";
DROP INDEX IF EXISTS "account_accountCategoryId_idx";
DROP INDEX IF EXISTS "account_class_idx";
DROP INDEX IF EXISTS "account_companyId_idx";

ALTER TABLE "account" DROP COLUMN "companyId";

ALTER TABLE "account" ADD CONSTRAINT "account_companyGroupId_fkey"
  FOREIGN KEY ("companyGroupId") REFERENCES "companyGroup"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "account" ADD CONSTRAINT "account_number_key" UNIQUE ("number", "companyGroupId");
ALTER TABLE "account" ADD CONSTRAINT "account_name_key" UNIQUE ("name", "companyGroupId");

CREATE INDEX "account_companyGroupId_idx" ON "account"("companyGroupId");
CREATE INDEX "account_number_idx" ON "account"("number", "companyGroupId");
CREATE INDEX "account_type_idx" ON "account"("type", "companyGroupId");
CREATE INDEX "account_incomeBalance_idx" ON "account"("incomeBalance", "companyGroupId");
CREATE INDEX "account_accountCategoryId_idx" ON "account"("accountCategoryId", "companyGroupId");
CREATE INDEX "account_class_idx" ON "account"("class", "companyGroupId");

-- 4b. accountCategory: companyId → companyGroupId

ALTER TABLE "accountCategory" ADD COLUMN "companyGroupId" TEXT;
UPDATE "accountCategory" SET "companyGroupId" = c."companyGroupId"
  FROM "company" c WHERE c."id" = "accountCategory"."companyId";
ALTER TABLE "accountCategory" ALTER COLUMN "companyGroupId" SET NOT NULL;

ALTER TABLE "accountCategory" DROP CONSTRAINT IF EXISTS "accountCategory_unique_category";
ALTER TABLE "accountCategory" DROP CONSTRAINT IF EXISTS "accountCategory_companyId_fkey";
DROP INDEX IF EXISTS "accountCategory_companyId_idx";

ALTER TABLE "accountCategory" DROP COLUMN "companyId";

ALTER TABLE "accountCategory" ADD CONSTRAINT "accountCategory_companyGroupId_fkey"
  FOREIGN KEY ("companyGroupId") REFERENCES "companyGroup"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "accountCategory" ADD CONSTRAINT "accountCategory_unique_category" UNIQUE ("category", "companyGroupId");

CREATE INDEX "accountCategory_companyGroupId_idx" ON "accountCategory"("companyGroupId");

-- 4c. currency: companyId → companyGroupId

ALTER TABLE "currency" ADD COLUMN "companyGroupId" TEXT;
UPDATE "currency" SET "companyGroupId" = c."companyGroupId"
  FROM "company" c WHERE c."id" = "currency"."companyId";
ALTER TABLE "currency" ALTER COLUMN "companyGroupId" SET NOT NULL;

ALTER TABLE "currency" DROP CONSTRAINT IF EXISTS "currency_code_key";
ALTER TABLE "currency" DROP CONSTRAINT IF EXISTS "currency_companyId_fkey";

ALTER TABLE "currency" DROP COLUMN "companyId";

ALTER TABLE "currency" ADD CONSTRAINT "currency_companyGroupId_fkey"
  FOREIGN KEY ("companyGroupId") REFERENCES "companyGroup"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "currency" ADD CONSTRAINT "currency_code_key" UNIQUE ("code", "companyGroupId");

CREATE INDEX "currency_companyGroupId_idx" ON "currency"("companyGroupId");

-- =====================================================
-- PART 5: Add companyGroupId to Operational Tables
-- =====================================================

-- Helper: backfill companyGroupId from company for all operational tables
-- Each table keeps its companyId (for operational scoping) and gains
-- companyGroupId (for FK references to group-scoped tables).

-- accountDefault: backfill account columns from numbers to IDs
DO $$
DECLARE
  col TEXT;
  cols TEXT[] := ARRAY[
    'salesAccount', 'salesDiscountAccount', 'costOfGoodsSoldAccount',
    'purchaseAccount', 'directCostAppliedAccount', 'overheadCostAppliedAccount',
    'purchaseVarianceAccount', 'inventoryAdjustmentVarianceAccount',
    'materialVarianceAccount', 'capacityVarianceAccount',
    'overheadAccount', 'maintenanceAccount',
    'assetDepreciationExpenseAccount', 'assetGainsAndLossesAccount',
    'serviceChargeAccount', 'interestAccount',
    'supplierPaymentDiscountAccount', 'customerPaymentDiscountAccount',
    'roundingAccount',
    'assetAquisitionCostAccount', 'assetAquisitionCostOnDisposalAccount',
    'accumulatedDepreciationAccount', 'accumulatedDepreciationOnDisposalAccount',
    'inventoryAccount', 'inventoryInterimAccrualAccount',
    'workInProgressAccount', 'receivablesAccount',
    'inventoryShippedNotInvoicedAccount',
    'bankCashAccount', 'bankLocalCurrencyAccount', 'bankForeignCurrencyAccount',
    'prepaymentAccount', 'payablesAccount',
    'inventoryReceivedNotInvoicedAccount',
    'salesTaxPayableAccount', 'reverseChargeSalesTaxPayableAccount',
    'purchaseTaxPayableAccount', 'retainedEarningsAccount'
  ];
BEGIN
  FOREACH col IN ARRAY cols
  LOOP
    EXECUTE format(
      'UPDATE "accountDefault" ad SET %I = a."id"
       FROM "account" a
       INNER JOIN "company" c ON c."companyGroupId" = a."companyGroupId"
       WHERE a."number" = ad.%I
         AND c."id" = ad."companyId"',
      col, col
    );
  END LOOP;
END;
$$;

ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_salesAccount_fkey"
  FOREIGN KEY ("salesAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_salesDiscountAccount_fkey"
  FOREIGN KEY ("salesDiscountAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_costOfGoodsSoldAccount_fkey"
  FOREIGN KEY ("costOfGoodsSoldAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_purchaseAccount_fkey"
  FOREIGN KEY ("purchaseAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_directCostAppliedAccount_fkey"
  FOREIGN KEY ("directCostAppliedAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_overheadCostAppliedAccount_fkey"
  FOREIGN KEY ("overheadCostAppliedAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_purchaseVarianceAccount_fkey"
  FOREIGN KEY ("purchaseVarianceAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_inventoryAdjustmentVarianceAccount_fkey"
  FOREIGN KEY ("inventoryAdjustmentVarianceAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_materialVarianceAccount_fkey"
  FOREIGN KEY ("materialVarianceAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_capacityVarianceAccount_fkey"
  FOREIGN KEY ("capacityVarianceAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_overheadAccount_fkey"
  FOREIGN KEY ("overheadAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_maintenanceAccount_fkey"
  FOREIGN KEY ("maintenanceAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_assetDepreciationExpenseAccount_fkey"
  FOREIGN KEY ("assetDepreciationExpenseAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_assetGainsAndLossesAccount_fkey"
  FOREIGN KEY ("assetGainsAndLossesAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_serviceChargeAccount_fkey"
  FOREIGN KEY ("serviceChargeAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_interestAccount_fkey"
  FOREIGN KEY ("interestAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_supplierPaymentDiscountAccount_fkey"
  FOREIGN KEY ("supplierPaymentDiscountAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_customerPaymentDiscountAccount_fkey"
  FOREIGN KEY ("customerPaymentDiscountAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_roundingAccount_fkey"
  FOREIGN KEY ("roundingAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_aquisitionCostAccount_fkey"
  FOREIGN KEY ("assetAquisitionCostAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_aquisitionCostOnDisposalAccount_fkey"
  FOREIGN KEY ("assetAquisitionCostOnDisposalAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_accumulatedDepreciationAccount_fkey"
  FOREIGN KEY ("accumulatedDepreciationAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_accumulatedDepreciationOnDisposalAccount_fkey"
  FOREIGN KEY ("accumulatedDepreciationOnDisposalAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_inventoryAccount_fkey"
  FOREIGN KEY ("inventoryAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_inventoryInterimAccrualAccount_fkey"
  FOREIGN KEY ("inventoryInterimAccrualAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_workInProgressAccount_fkey"
  FOREIGN KEY ("workInProgressAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_receivablesAccount_fkey"
  FOREIGN KEY ("receivablesAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_inventoryShippedNotInvoicedAccount_fkey"
  FOREIGN KEY ("inventoryShippedNotInvoicedAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_bankCashAccount_fkey"
  FOREIGN KEY ("bankCashAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_bankLocalCurrencyAccount_fkey"
  FOREIGN KEY ("bankLocalCurrencyAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_bankForeignCurrencyAccount_fkey"
  FOREIGN KEY ("bankForeignCurrencyAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_prepaymentAccount_fkey"
  FOREIGN KEY ("prepaymentAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_payablesAccount_fkey"
  FOREIGN KEY ("payablesAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_inventoryReceivedNotInvoicedAccount_fkey"
  FOREIGN KEY ("inventoryReceivedNotInvoicedAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_salesTaxPayableAccount_fkey"
  FOREIGN KEY ("salesTaxPayableAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_reverseChargeSalesTaxPayableAccount_fkey"
  FOREIGN KEY ("reverseChargeSalesTaxPayableAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_purchaseTaxPayableAccount_fkey"
  FOREIGN KEY ("purchaseTaxPayableAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_retainedEarningsAccount_fkey"
  FOREIGN KEY ("retainedEarningsAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- journalLine: make accountNumber nullable, add accountId, backfill from account table, simple FK
ALTER TABLE "journalLine" ALTER COLUMN "accountNumber" DROP NOT NULL;
ALTER TABLE "journalLine" ADD COLUMN "accountId" TEXT;
UPDATE "journalLine" SET "accountId" = a."id"
  FROM "account" a
  INNER JOIN "company" c ON c."companyGroupId" = a."companyGroupId"
  WHERE a."number" = "journalLine"."accountNumber"
    AND c."id" = "journalLine"."companyId";
ALTER TABLE "journalLine" ADD CONSTRAINT "journalLine_accountId_fkey"
  FOREIGN KEY ("accountId") REFERENCES "account"("id") ON UPDATE CASCADE ON DELETE SET NULL;
CREATE INDEX "journalLine_accountId_idx" ON "journalLine"("accountId");

-- purchaseOrderLine: add accountId, backfill, simple FK
ALTER TABLE "purchaseOrderLine" ADD COLUMN "accountId" TEXT;
UPDATE "purchaseOrderLine" SET "accountId" = a."id"
  FROM "account" a
  INNER JOIN "company" c ON c."companyGroupId" = a."companyGroupId"
  WHERE a."number" = "purchaseOrderLine"."accountNumber"
    AND c."id" = "purchaseOrderLine"."companyId";
ALTER TABLE "purchaseOrderLine" ADD CONSTRAINT "purchaseOrderLine_accountId_fkey"
  FOREIGN KEY ("accountId") REFERENCES "account"("id") ON UPDATE CASCADE ON DELETE SET NULL;
CREATE INDEX "purchaseOrderLine_accountId_idx" ON "purchaseOrderLine"("accountId");

-- salesOrderLine: add accountId, backfill, simple FK
ALTER TABLE "salesOrderLine" ADD COLUMN "accountId" TEXT;
UPDATE "salesOrderLine" SET "accountId" = a."id"
  FROM "account" a
  INNER JOIN "company" c ON c."companyGroupId" = a."companyGroupId"
  WHERE a."number" = "salesOrderLine"."accountNumber"
    AND c."id" = "salesOrderLine"."companyId";
ALTER TABLE "salesOrderLine" ADD CONSTRAINT "salesOrderLine_accountId_fkey"
  FOREIGN KEY ("accountId") REFERENCES "account"("id") ON UPDATE CASCADE ON DELETE SET NULL;
CREATE INDEX "salesOrderLine_accountId_idx" ON "salesOrderLine"("accountId");

-- salesInvoiceLine: add accountId, backfill, simple FK
ALTER TABLE "salesInvoiceLine" ADD COLUMN "accountId" TEXT;
UPDATE "salesInvoiceLine" SET "accountId" = a."id"
  FROM "account" a
  INNER JOIN "company" c ON c."companyGroupId" = a."companyGroupId"
  WHERE a."number" = "salesInvoiceLine"."accountNumber"
    AND c."id" = "salesInvoiceLine"."companyId";
ALTER TABLE "salesInvoiceLine" ADD CONSTRAINT "salesInvoiceLine_accountId_fkey"
  FOREIGN KEY ("accountId") REFERENCES "account"("id") ON UPDATE CASCADE ON DELETE SET NULL;
CREATE INDEX "salesInvoiceLine_accountId_idx" ON "salesInvoiceLine"("accountId");

-- purchaseInvoiceLine: add accountId, backfill, simple FK
ALTER TABLE "purchaseInvoiceLine" ADD COLUMN "accountId" TEXT;
UPDATE "purchaseInvoiceLine" SET "accountId" = a."id"
  FROM "account" a
  INNER JOIN "company" c ON c."companyGroupId" = a."companyGroupId"
  WHERE a."number" = "purchaseInvoiceLine"."accountNumber"
    AND c."id" = "purchaseInvoiceLine"."companyId";
ALTER TABLE "purchaseInvoiceLine" ADD CONSTRAINT "purchaseInvoiceLine_accountId_fkey"
  FOREIGN KEY ("accountId") REFERENCES "account"("id") ON UPDATE CASCADE ON DELETE SET NULL;
CREATE INDEX "purchaseInvoiceLine_accountId_idx" ON "purchaseInvoiceLine"("accountId");

-- Drop views that use SELECT * from line tables (they depend on accountNumber column)
DROP VIEW IF EXISTS "purchaseOrderLines";
DROP VIEW IF EXISTS "purchaseInvoiceLines";
DROP VIEW IF EXISTS "salesOrderLines";
DROP VIEW IF EXISTS "salesInvoiceLines";

-- Drop CHECK constraints that reference accountNumber
ALTER TABLE "purchaseOrderLine" DROP CONSTRAINT IF EXISTS "purchaseOrderLineType_number";
ALTER TABLE "purchaseInvoiceLine" DROP CONSTRAINT IF EXISTS "invoiceLineType_number";
ALTER TABLE "salesOrderLine" DROP CONSTRAINT IF EXISTS "salesOrderLineType_number";

-- Drop accountNumber columns (data has been backfilled to accountId above)
ALTER TABLE "journalLine" DROP COLUMN "accountNumber";
DROP INDEX IF EXISTS "journalLine_accountNumber_idx";
ALTER TABLE "purchaseOrderLine" DROP COLUMN "accountNumber";
ALTER TABLE "salesOrderLine" DROP COLUMN "accountNumber";
ALTER TABLE "purchaseInvoiceLine" DROP COLUMN "accountNumber";
ALTER TABLE "salesInvoiceLine" DROP COLUMN "accountNumber";

-- Recreate CHECK constraints using accountId
ALTER TABLE "purchaseOrderLine" ADD CONSTRAINT "purchaseOrderLineType_check"
  CHECK (
    (
      "purchaseOrderLineType" = 'Comment' AND
      "itemId" IS NULL AND
      "accountId" IS NULL AND
      "assetId" IS NULL AND
      "description" IS NOT NULL
    )
    OR (
      "purchaseOrderLineType" = 'G/L Account' AND
      "itemId" IS NULL AND
      "accountId" IS NOT NULL AND
      "assetId" IS NULL
    )
    OR (
      (
        "purchaseOrderLineType" = 'Part' OR
        "purchaseOrderLineType" = 'Material' OR
        "purchaseOrderLineType" = 'Tool' OR
        "purchaseOrderLineType" = 'Consumable' OR
        "purchaseOrderLineType" = 'Fixture' OR
        "purchaseOrderLineType" = 'Service'
      ) AND
      "itemId" IS NOT NULL AND
      "accountId" IS NULL AND
      "assetId" IS NULL
    ) OR (
      "purchaseOrderLineType" = 'Fixed Asset' AND
      "itemId" IS NULL AND
      "accountId" IS NULL AND
      "assetId" IS NOT NULL
    )
  );

ALTER TABLE "purchaseInvoiceLine" ADD CONSTRAINT "invoiceLineType_check"
  CHECK (
    (
      "invoiceLineType" = 'Comment' AND
      "itemId" IS NULL AND
      "accountId" IS NULL AND
      "assetId" IS NULL AND
      "description" IS NOT NULL
    )
    OR (
      "invoiceLineType" = 'G/L Account' AND
      "itemId" IS NULL AND
      "accountId" IS NOT NULL AND
      "assetId" IS NULL
    )
    OR (
      (
        "invoiceLineType" = 'Part' OR
        "invoiceLineType" = 'Material' OR
        "invoiceLineType" = 'Tool' OR
        "invoiceLineType" = 'Consumable' OR
        "invoiceLineType" = 'Fixture' OR
        "invoiceLineType" = 'Service'
      ) AND
      "itemId" IS NOT NULL AND
      "accountId" IS NULL AND
      "assetId" IS NULL
    )
    OR (
      "invoiceLineType" = 'Fixed Asset' AND
      "itemId" IS NULL AND
      "accountId" IS NULL AND
      "assetId" IS NOT NULL
    )
  );

ALTER TABLE "salesOrderLine" ADD CONSTRAINT "salesOrderLineType_check"
  CHECK (
    (
      "salesOrderLineType" = 'Comment' AND
      "itemId" IS NULL AND
      "accountId" IS NULL AND
      "assetId" IS NULL AND
      "description" IS NOT NULL
    )
    OR (
      (
        "salesOrderLineType" = 'Part' OR
        "salesOrderLineType" = 'Material' OR
        "salesOrderLineType" = 'Tool' OR
        "salesOrderLineType" = 'Consumable' OR
        "salesOrderLineType" = 'Fixture' OR
        "salesOrderLineType" = 'Service'
      ) AND
      "itemId" IS NOT NULL AND
      "accountId" IS NULL AND
      "assetId" IS NULL
    ) OR (
      "salesOrderLineType" = 'Fixed Asset' AND
      "itemId" IS NULL AND
      "accountId" IS NULL AND
      "assetId" IS NOT NULL
    )
  );

-- Recreate views that were dropped for the accountNumber column removal
CREATE OR REPLACE VIEW "purchaseOrderLines" WITH(SECURITY_INVOKER=true) AS (
  SELECT DISTINCT ON (pl.id)
    pl.*,
    CASE
      WHEN i."thumbnailPath" IS NULL AND mu."thumbnailPath" IS NOT NULL THEN mu."thumbnailPath"
      WHEN i."thumbnailPath" IS NULL AND imu."thumbnailPath" IS NOT NULL THEN imu."thumbnailPath"
      ELSE i."thumbnailPath"
    END as "thumbnailPath",
    i.name as "itemName",
    i."readableIdWithRevision" as "itemReadableId",
    i.description as "itemDescription",
    COALESCE(mu.id, imu.id) as "modelId",
    COALESCE(mu."autodeskUrn", imu."autodeskUrn") as "autodeskUrn",
    COALESCE(mu."modelPath", imu."modelPath") as "modelPath",
    COALESCE(mu."name", imu."name") as "modelName",
    COALESCE(mu."size", imu."size") as "modelSize",
    ic."unitCost" as "unitCost",
    sp."supplierPartId",
    jo."description" as "jobOperationDescription"
  FROM "purchaseOrderLine" pl
  INNER JOIN "purchaseOrder" so ON so.id = pl."purchaseOrderId"
  LEFT JOIN "modelUpload" mu ON pl."modelUploadId" = mu."id"
  INNER JOIN "item" i ON i.id = pl."itemId"
  LEFT JOIN "itemCost" ic ON ic."itemId" = i.id
  LEFT JOIN "modelUpload" imu ON imu.id = i."modelUploadId"
  LEFT JOIN "supplierPart" sp ON sp."supplierId" = so."supplierId" AND sp."itemId" = i.id
  LEFT JOIN "jobOperation" jo ON jo."id" = pl."jobOperationId"
);

CREATE OR REPLACE VIEW "purchaseInvoiceLines" WITH(SECURITY_INVOKER=true) AS (
  SELECT
    pl.*,
    CASE
      WHEN i."thumbnailPath" IS NULL AND mu."thumbnailPath" IS NOT NULL THEN mu."thumbnailPath"
      WHEN i."thumbnailPath" IS NULL AND imu."thumbnailPath" IS NOT NULL THEN imu."thumbnailPath"
      ELSE i."thumbnailPath"
    END as "thumbnailPath",
    i."readableIdWithRevision" as "itemReadableId",
    i.name as "itemName",
    i.description as "itemDescription",
    ic."unitCost" as "unitCost",
    sp."supplierPartId"
  FROM "purchaseInvoiceLine" pl
  INNER JOIN "purchaseInvoice" pi ON pi.id = pl."invoiceId"
  LEFT JOIN "modelUpload" mu ON pl."modelUploadId" = mu."id"
  INNER JOIN "item" i ON i.id = pl."itemId"
  LEFT JOIN "itemCost" ic ON ic."itemId" = i.id
  LEFT JOIN "modelUpload" imu ON imu.id = i."modelUploadId"
  LEFT JOIN "supplierPart" sp ON sp."supplierId" = pi."supplierId" AND sp."itemId" = i.id
);

CREATE OR REPLACE VIEW "salesOrderLines" WITH(SECURITY_INVOKER=true) AS (
  SELECT
    sl.*,
    i."readableIdWithRevision" as "itemReadableId",
    CASE
      WHEN i."thumbnailPath" IS NULL AND mu."thumbnailPath" IS NOT NULL THEN mu."thumbnailPath"
      WHEN i."thumbnailPath" IS NULL AND imu."thumbnailPath" IS NOT NULL THEN imu."thumbnailPath"
      ELSE i."thumbnailPath"
    END as "thumbnailPath",
    COALESCE(mu.id, imu.id) as "modelId",
    COALESCE(mu."autodeskUrn", imu."autodeskUrn") as "autodeskUrn",
    COALESCE(mu."modelPath", imu."modelPath") as "modelPath",
    COALESCE(mu."name", imu."name") as "modelName",
    COALESCE(mu."size", imu."size") as "modelSize",
    ic."unitCost" as "unitCost",
    cp."customerPartId",
    cp."customerPartRevision",
    so."orderDate",
    so."customerId",
    so."salesOrderId" as "salesOrderReadableId"
  FROM "salesOrderLine" sl
  INNER JOIN "salesOrder" so ON so.id = sl."salesOrderId"
  LEFT JOIN "modelUpload" mu ON sl."modelUploadId" = mu."id"
  INNER JOIN "item" i ON i.id = sl."itemId"
  LEFT JOIN "itemCost" ic ON ic."itemId" = i.id
  LEFT JOIN "modelUpload" imu ON imu.id = i."modelUploadId"
  LEFT JOIN "customerPartToItem" cp ON cp."customerId" = so."customerId" AND cp."itemId" = i.id
);

CREATE OR REPLACE VIEW "salesInvoiceLines" WITH(SECURITY_INVOKER=true) AS (
  SELECT
    sl.*,
    i."readableIdWithRevision" as "itemReadableId",
    CASE
      WHEN i."thumbnailPath" IS NULL AND mu."thumbnailPath" IS NOT NULL THEN mu."thumbnailPath"
      WHEN i."thumbnailPath" IS NULL AND imu."thumbnailPath" IS NOT NULL THEN imu."thumbnailPath"
      ELSE i."thumbnailPath"
    END as "thumbnailPath",
    i.name as "itemName",
    i.description as "itemDescription",
    ic."unitCost" as "unitCost",
    (SELECT cp."customerPartId"
     FROM "customerPartToItem" cp
     WHERE cp."customerId" = si."customerId" AND cp."itemId" = i.id
     LIMIT 1) as "customerPartId"
  FROM "salesInvoiceLine" sl
  INNER JOIN "salesInvoice" si ON si.id = sl."invoiceId"
  LEFT JOIN "modelUpload" mu ON sl."modelUploadId" = mu."id"
  INNER JOIN "item" i ON i.id = sl."itemId"
  LEFT JOIN "itemCost" ic ON ic."itemId" = i.id
  LEFT JOIN "modelUpload" imu ON imu.id = i."modelUploadId"
);

-- shippingMethod: convert carrierAccountId from account number to account id
UPDATE "shippingMethod" SET "carrierAccountId" = a."id"
  FROM "account" a
  INNER JOIN "company" c ON c."companyGroupId" = a."companyGroupId"
  WHERE a."number" = "shippingMethod"."carrierAccountId"
    AND c."id" = "shippingMethod"."companyId";
ALTER TABLE "shippingMethod" ADD CONSTRAINT "shippingMethod_carrierAccountId_fkey"
  FOREIGN KEY ("carrierAccountId") REFERENCES "account"("id") ON UPDATE CASCADE ON DELETE SET NULL;

-- Currency FK tables: simple FK to currencyCode reference table
-- (purchaseInvoiceLine, purchaseOrderPayment, salesOrderPayment, quotePayment,
--  customerPayment, supplierPayment had their currencyCode column dropped in
--  earlier migrations — no FK needed)

ALTER TABLE "purchaseInvoice" ADD CONSTRAINT "purchaseInvoice_currencyCode_fkey"
  FOREIGN KEY ("currencyCode") REFERENCES "currencyCode"("code") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "purchasePayment" ADD CONSTRAINT "purchasePayment_currencyCode_fkey"
  FOREIGN KEY ("currencyCode") REFERENCES "currencyCode"("code") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "itemUnitSalePrice" ADD CONSTRAINT "itemUnitSalePrice_currencyCode_fkey"
  FOREIGN KEY ("currencyCode") REFERENCES "currencyCode"("code") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "salesOrder" ADD CONSTRAINT "salesOrder_currencyCode_fkey"
  FOREIGN KEY ("currencyCode") REFERENCES "currencyCode"("code") ON DELETE SET NULL ON UPDATE CASCADE;


-- =====================================================
-- PART 6: New RLS Policies on Shared Tables
-- =====================================================

-- account: SELECT for any employee in group, write for root company permission
CREATE POLICY "SELECT" ON "public"."account"
FOR SELECT USING (
  "companyGroupId" = ANY (
    (SELECT get_company_groups_for_employee())::text[]
  )
);

CREATE POLICY "INSERT" ON "public"."account"
FOR INSERT WITH CHECK (
  "companyGroupId" = ANY (
    (SELECT get_company_groups_for_root_permission('accounting_create'))::text[]
  )
);

CREATE POLICY "UPDATE" ON "public"."account"
FOR UPDATE USING (
  "companyGroupId" = ANY (
    (SELECT get_company_groups_for_root_permission('accounting_update'))::text[]
  )
);

CREATE POLICY "DELETE" ON "public"."account"
FOR DELETE USING (
  "companyGroupId" = ANY (
    (SELECT get_company_groups_for_root_permission('accounting_delete'))::text[]
  )
);

-- accountCategory: same pattern as account
CREATE POLICY "SELECT" ON "public"."accountCategory"
FOR SELECT USING (
  "companyGroupId" = ANY (
    (SELECT get_company_groups_for_employee())::text[]
  )
);

CREATE POLICY "INSERT" ON "public"."accountCategory"
FOR INSERT WITH CHECK (
  "companyGroupId" = ANY (
    (SELECT get_company_groups_for_root_permission('accounting_create'))::text[]
  )
);

CREATE POLICY "UPDATE" ON "public"."accountCategory"
FOR UPDATE USING (
  "companyGroupId" = ANY (
    (SELECT get_company_groups_for_root_permission('accounting_update'))::text[]
  )
);

CREATE POLICY "DELETE" ON "public"."accountCategory"
FOR DELETE USING (
  "companyGroupId" = ANY (
    (SELECT get_company_groups_for_root_permission('accounting_delete'))::text[]
  )
);

-- accountSubcategory: derives group from accountCategory
CREATE POLICY "SELECT" ON "public"."accountSubcategory"
FOR SELECT USING (
  (SELECT "companyGroupId" FROM "accountCategory" WHERE "id" = "accountCategoryId") = ANY (
    (SELECT get_company_groups_for_employee())::text[]
  )
);

CREATE POLICY "INSERT" ON "public"."accountSubcategory"
FOR INSERT WITH CHECK (
  (SELECT "companyGroupId" FROM "accountCategory" WHERE "id" = "accountCategoryId") = ANY (
    (SELECT get_company_groups_for_root_permission('accounting_create'))::text[]
  )
);

CREATE POLICY "UPDATE" ON "public"."accountSubcategory"
FOR UPDATE USING (
  (SELECT "companyGroupId" FROM "accountCategory" WHERE "id" = "accountCategoryId") = ANY (
    (SELECT get_company_groups_for_root_permission('accounting_update'))::text[]
  )
);

CREATE POLICY "DELETE" ON "public"."accountSubcategory"
FOR DELETE USING (
  (SELECT "companyGroupId" FROM "accountCategory" WHERE "id" = "accountCategoryId") = ANY (
    (SELECT get_company_groups_for_root_permission('accounting_delete'))::text[]
  )
);

-- currency: SELECT for any employee in group, write for root company permission
CREATE POLICY "SELECT" ON "public"."currency"
FOR SELECT USING (
  "companyGroupId" = ANY (
    (SELECT get_company_groups_for_employee())::text[]
  )
);

CREATE POLICY "INSERT" ON "public"."currency"
FOR INSERT WITH CHECK (
  "companyGroupId" = ANY (
    (SELECT get_company_groups_for_root_permission('accounting_create'))::text[]
  )
);

CREATE POLICY "UPDATE" ON "public"."currency"
FOR UPDATE USING (
  "companyGroupId" = ANY (
    (SELECT get_company_groups_for_root_permission('accounting_update'))::text[]
  )
);

CREATE POLICY "DELETE" ON "public"."currency"
FOR DELETE USING (
  "companyGroupId" = ANY (
    (SELECT get_company_groups_for_root_permission('accounting_delete'))::text[]
  )
);

-- =====================================================
-- PART 7: Recreate Views
-- =====================================================

CREATE OR REPLACE VIEW "accountCategories" WITH(SECURITY_INVOKER=true) AS
  SELECT
    "id",
    "category",
    "class",
    "incomeBalance",
    "companyGroupId",
    "createdBy",
    "createdAt",
    "updatedBy",
    "updatedAt",
    "customFields",
    (SELECT count(*) FROM "accountSubcategory" WHERE "accountSubcategory"."accountCategoryId" = "accountCategory"."id" AND "accountSubcategory"."active" = true) AS "subCategoriesCount"
  FROM "accountCategory"
;

CREATE OR REPLACE VIEW "accounts" WITH(SECURITY_INVOKER=true) AS
  SELECT
    "account".*,
    (SELECT "category" FROM "accountCategory" WHERE "accountCategory"."id" = "account"."accountCategoryId") AS "accountCategory",
    (SELECT "name" FROM "accountSubcategory" WHERE "accountSubcategory"."id" = "account"."accountSubcategoryId") AS "accountSubCategory"
  FROM "account"
;

CREATE OR REPLACE VIEW "currencies" WITH(SECURITY_INVOKER=true) AS
  SELECT c.*, cc."name"
  FROM "currency" c
  INNER JOIN "currencyCode" cc
    ON cc."code" = c."code";
