-- Reset Chart of Accounts
--
-- Replaces old chart of accounts with new tree-based structure for all
-- existing company groups. Temporarily drops FK constraints, clears
-- dependent data, inserts new accounts, re-seeds account defaults,
-- and re-adds all FK constraints.

-- ============================================================
-- Phase 1: Drop all FK constraints referencing account
-- ============================================================

-- Self-referential
ALTER TABLE "account" DROP CONSTRAINT IF EXISTS "account_parentId_fkey";

-- accountDefault FKs (drop all, including ones we're about to remove)
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
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_indirectCostAccount_fkey";
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
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_goodsReceivedNotInvoicedAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_bankCashAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_bankLocalCurrencyAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_bankForeignCurrencyAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_prepaymentAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_payablesAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_inventoryReceivedNotInvoicedAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_inventoryInvoicedNotReceivedAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_salesTaxPayableAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_reverseChargeSalesTaxPayableAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_purchaseTaxPayableAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_retainedEarningsAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_currencyTranslationAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_laborAndMachineVarianceAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_lotSizeVarianceAccount_fkey";
ALTER TABLE "accountDefault" DROP CONSTRAINT IF EXISTS "accountDefault_subcontractingVarianceAccount_fkey";

-- journalLine
ALTER TABLE "journalLine" DROP CONSTRAINT IF EXISTS "journalLine_accountId_fkey";

-- purchaseOrderLine
ALTER TABLE "purchaseOrderLine" DROP CONSTRAINT IF EXISTS "purchaseOrderLine_accountId_fkey";

-- salesOrderLine
ALTER TABLE "salesOrderLine" DROP CONSTRAINT IF EXISTS "salesOrderLine_accountId_fkey";

-- salesInvoiceLine
ALTER TABLE "salesInvoiceLine" DROP CONSTRAINT IF EXISTS "salesInvoiceLine_accountId_fkey";

-- purchaseInvoiceLine
ALTER TABLE "purchaseInvoiceLine" DROP CONSTRAINT IF EXISTS "purchaseInvoiceLine_accountId_fkey";

-- shippingMethod
ALTER TABLE "shippingMethod" DROP CONSTRAINT IF EXISTS "shippingMethod_carrierAccountId_fkey";


-- ============================================================
-- Phase 2: Delete/null dependent data
-- ============================================================

DELETE FROM "journalLineDimension";
DELETE FROM "journalLine";
DELETE FROM "journal";
DELETE FROM "accountDefault";

UPDATE "purchaseOrderLine" SET "accountId" = NULL WHERE "accountId" IS NOT NULL;
UPDATE "salesOrderLine" SET "accountId" = NULL WHERE "accountId" IS NOT NULL;
UPDATE "salesInvoiceLine" SET "accountId" = NULL WHERE "accountId" IS NOT NULL;
UPDATE "purchaseInvoiceLine" SET "accountId" = NULL WHERE "accountId" IS NOT NULL;
UPDATE "shippingMethod" SET "carrierAccountId" = NULL WHERE "carrierAccountId" IS NOT NULL;


-- ============================================================
-- Phase 2.5: Alter accountDefault table — GR/IR clearing refactor
-- ============================================================

-- Drop legacy Business Central clearing accounts
ALTER TABLE "accountDefault" DROP COLUMN IF EXISTS "directCostAppliedAccount";
ALTER TABLE "accountDefault" DROP COLUMN IF EXISTS "purchaseAccount";
ALTER TABLE "accountDefault" DROP COLUMN IF EXISTS "overheadCostAppliedAccount";
ALTER TABLE "accountDefault" DROP COLUMN IF EXISTS "inventoryInterimAccrualAccount";
ALTER TABLE "accountDefault" DROP COLUMN IF EXISTS "inventoryReceivedNotInvoicedAccount";
ALTER TABLE "accountDefault" DROP COLUMN IF EXISTS "inventoryInvoicedNotReceivedAccount";

-- Rename overheadAccount → indirectCostAccount (non-inventory purchase expense)
ALTER TABLE "accountDefault" RENAME COLUMN "overheadAccount" TO "indirectCostAccount";

-- Rename capacityVarianceAccount → laborAndMachineVarianceAccount
ALTER TABLE "accountDefault" RENAME COLUMN "capacityVarianceAccount" TO "laborAndMachineVarianceAccount";

-- Add new GR/IR clearing account (single balance sheet clearing account)
ALTER TABLE "accountDefault" ADD COLUMN IF NOT EXISTS "goodsReceivedNotInvoicedAccount" TEXT;

-- Add new variance accounts
ALTER TABLE "accountDefault" ADD COLUMN IF NOT EXISTS "overheadVarianceAccount" TEXT;
ALTER TABLE "accountDefault" ADD COLUMN IF NOT EXISTS "lotSizeVarianceAccount" TEXT;
ALTER TABLE "accountDefault" ADD COLUMN IF NOT EXISTS "subcontractingVarianceAccount" TEXT;
ALTER TABLE "accountDefault" ADD COLUMN IF NOT EXISTS "currencyTranslationAccount" TEXT;
ALTER TABLE "accountDefault" ADD COLUMN IF NOT EXISTS "laborAbsorptionAccount" TEXT;


-- ============================================================
-- Phase 3: Delete all accounts
-- ============================================================

DELETE FROM "account";


-- ============================================================
-- Phase 3.5: Ensure isSystem column exists (added later in protect-root-accounts,
-- but needed here for the INSERT)
-- ============================================================

ALTER TABLE "account" ADD COLUMN IF NOT EXISTS "isSystem" BOOLEAN NOT NULL DEFAULT false;

-- ============================================================
-- Phase 4: Insert new accounts for every companyGroup
-- ============================================================

DO $$
DECLARE
  cg_id TEXT;
  key_to_id HSTORE;
  acc RECORD;
  new_id TEXT;
  parent_id TEXT;
BEGIN
  FOR cg_id IN SELECT id FROM "companyGroup"
  LOOP
    key_to_id := ''::hstore;

    FOR acc IN
      SELECT *
      FROM (VALUES
        -- BALANCE SHEET
        ('balance-sheet', NULL::TEXT, 'Balance Sheet', TRUE, NULL::TEXT, NULL::TEXT, 'Balance Sheet', NULL::TEXT, TRUE),

        -- ASSETS
        ('assets', NULL, 'Assets', TRUE, 'balance-sheet', NULL, 'Balance Sheet', 'Asset', FALSE),

        ('cash-and-bank', NULL, 'Cash & Bank', TRUE, 'assets', NULL, 'Balance Sheet', 'Asset', FALSE),
        ('1010', '1010', 'Bank - Cash', FALSE, 'cash-and-bank', 'Bank', 'Balance Sheet', 'Asset', FALSE),
        ('1020', '1020', 'Bank - Local Currency', FALSE, 'cash-and-bank', 'Bank', 'Balance Sheet', 'Asset', FALSE),
        ('1030', '1030', 'Bank - Foreign Currency', FALSE, 'cash-and-bank', 'Bank', 'Balance Sheet', 'Asset', FALSE),

        ('receivables', NULL, 'Receivables', TRUE, 'assets', NULL, 'Balance Sheet', 'Asset', FALSE),
        ('1110', '1110', 'Accounts Receivable', FALSE, 'receivables', 'Accounts Receivable', 'Balance Sheet', 'Asset', FALSE),
        ('1130', '1130', 'Inter-Company Receivables', FALSE, 'receivables', 'Accounts Receivable', 'Balance Sheet', 'Asset', FALSE),

        ('inventory', NULL, 'Inventory & Stock', TRUE, 'assets', NULL, 'Balance Sheet', 'Asset', FALSE),
        ('1210', '1210', 'Inventory', FALSE, 'inventory', 'Inventory', 'Balance Sheet', 'Asset', FALSE),
        ('1230', '1230', 'Work In Progress (WIP)', FALSE, 'inventory', 'Inventory', 'Balance Sheet', 'Asset', FALSE),
        ('1240', '1240', 'Inventory Reserves / Allowances', FALSE, 'inventory', 'Inventory', 'Balance Sheet', 'Asset', FALSE),

        ('ppe', NULL, 'Property, Plant & Equipment', TRUE, 'assets', NULL, 'Balance Sheet', 'Asset', FALSE),
        ('1310', '1310', 'Fixed Asset Acquisition Cost', FALSE, 'ppe', 'Fixed Asset', 'Balance Sheet', 'Asset', FALSE),
        ('1320', '1320', 'Fixed Asset Acquisition Cost on Disposal', FALSE, 'ppe', 'Fixed Asset', 'Balance Sheet', 'Asset', FALSE),
        ('1330', '1330', 'Accumulated Depreciation', FALSE, 'ppe', 'Accumulated Depreciation', 'Balance Sheet', 'Asset', FALSE),
        ('1340', '1340', 'Accumulated Depreciation on Disposal', FALSE, 'ppe', 'Accumulated Depreciation', 'Balance Sheet', 'Asset', FALSE),
        ('1350', '1350', 'Machinery & Equipment', FALSE, 'ppe', 'Fixed Asset', 'Balance Sheet', 'Asset', FALSE),
        ('1360', '1360', 'Buildings & Leasehold Improvements', FALSE, 'ppe', 'Fixed Asset', 'Balance Sheet', 'Asset', FALSE),

        ('other-assets', NULL, 'Other Assets', TRUE, 'assets', NULL, 'Balance Sheet', 'Asset', FALSE),
        ('1410', '1410', 'Intangible Assets', FALSE, 'other-assets', 'Other Asset', 'Balance Sheet', 'Asset', FALSE),
        ('1420', '1420', 'Accumulated Amortization', FALSE, 'other-assets', 'Other Asset', 'Balance Sheet', 'Asset', FALSE),
        ('1430', '1430', 'Investments in Subsidiaries', FALSE, 'other-assets', 'Investments', 'Balance Sheet', 'Asset', FALSE),
        ('1440', '1440', 'Deferred Tax Assets', FALSE, 'other-assets', 'Other Asset', 'Balance Sheet', 'Asset', FALSE),

        -- LIABILITIES
        ('liabilities', NULL, 'Liabilities', TRUE, 'balance-sheet', NULL, 'Balance Sheet', 'Liability', FALSE),

        ('payables', NULL, 'Payables', TRUE, 'liabilities', NULL, 'Balance Sheet', 'Liability', FALSE),
        ('2010', '2010', 'Accounts Payable', FALSE, 'payables', 'Accounts Payable', 'Balance Sheet', 'Liability', FALSE),
        ('2020', '2020', 'Inter-Company Payables', FALSE, 'payables', 'Accounts Payable', 'Balance Sheet', 'Liability', FALSE),

        ('current-liabilities', NULL, 'Current Liabilities', TRUE, 'liabilities', NULL, 'Balance Sheet', 'Liability', FALSE),
        ('2110', '2110', 'Customer Prepayments', FALSE, 'current-liabilities', 'Other Current Liability', 'Balance Sheet', 'Liability', FALSE),
        ('2125', '2125', 'GR/IR Clearing', FALSE, 'current-liabilities', 'Other Current Liability', 'Balance Sheet', 'Liability', FALSE),
        ('2130', '2130', 'Inventory Shipped Not Invoiced', FALSE, 'current-liabilities', 'Other Current Liability', 'Balance Sheet', 'Liability', FALSE),
        ('2140', '2140', 'Accrued Expenses', FALSE, 'current-liabilities', 'Other Current Liability', 'Balance Sheet', 'Liability', FALSE),
        ('2150', '2150', 'Accrued Wages & Salaries', FALSE, 'current-liabilities', 'Other Current Liability', 'Balance Sheet', 'Liability', FALSE),
        ('2160', '2160', 'Deferred Revenue', FALSE, 'current-liabilities', 'Other Current Liability', 'Balance Sheet', 'Liability', FALSE),
        ('2170', '2170', 'Short-Term Loans', FALSE, 'current-liabilities', 'Other Current Liability', 'Balance Sheet', 'Liability', FALSE),

        ('tax-liabilities', NULL, 'Tax Liabilities', TRUE, 'liabilities', NULL, 'Balance Sheet', 'Liability', FALSE),
        ('2210', '2210', 'Sales Tax Payable', FALSE, 'tax-liabilities', 'Tax', 'Balance Sheet', 'Liability', FALSE),
        ('2220', '2220', 'Purchase Tax Payable', FALSE, 'tax-liabilities', 'Tax', 'Balance Sheet', 'Liability', FALSE),
        ('2230', '2230', 'Reverse Charge Tax Payable', FALSE, 'tax-liabilities', 'Tax', 'Balance Sheet', 'Liability', FALSE),

        ('long-term-liabilities', NULL, 'Long-Term Liabilities', TRUE, 'liabilities', NULL, 'Balance Sheet', 'Liability', FALSE),
        ('2410', '2410', 'Long-Term Debt / Loans', FALSE, 'long-term-liabilities', 'Long Term Liability', 'Balance Sheet', 'Liability', FALSE),
        ('2420', '2420', 'Deferred Tax Liabilities', FALSE, 'long-term-liabilities', 'Long Term Liability', 'Balance Sheet', 'Liability', FALSE),
        ('2430', '2430', 'Pension Obligations', FALSE, 'long-term-liabilities', 'Long Term Liability', 'Balance Sheet', 'Liability', FALSE),

        -- EQUITY
        ('equity', NULL, 'Equity', TRUE, 'balance-sheet', NULL, 'Balance Sheet', 'Equity', FALSE),
        ('3010', '3010', 'Common Stock / Share Capital', FALSE, 'equity', 'Equity - No Close', 'Balance Sheet', 'Equity', FALSE),
        ('3100', '3100', 'Retained Earnings', FALSE, 'equity', 'Retained Earnings', 'Balance Sheet', 'Equity', FALSE),
        ('3200', '3200', 'Reserves (Currency Translation)', FALSE, 'equity', 'Equity - Close', 'Balance Sheet', 'Equity', FALSE),
        ('3300', '3300', 'Dividends Payable', FALSE, 'equity', 'Equity - Close', 'Balance Sheet', 'Equity', FALSE),

        -- INCOME STATEMENT
        ('income-statement', NULL, 'Income Statement', TRUE, NULL, NULL, 'Income Statement', NULL, TRUE),

        -- REVENUE
        ('revenue', NULL, 'Revenue', TRUE, 'income-statement', NULL, 'Income Statement', 'Revenue', FALSE),
        ('4010', '4010', 'Sales', FALSE, 'revenue', 'Income', 'Income Statement', 'Revenue', FALSE),
        ('4020', '4020', 'Sales Discounts', FALSE, 'revenue', 'Income', 'Income Statement', 'Revenue', FALSE),
        ('4030', '4030', 'Manufacturing Services Revenue', FALSE, 'revenue', 'Income', 'Income Statement', 'Revenue', FALSE),

        ('other-income', NULL, 'Other Income', TRUE, 'income-statement', NULL, 'Income Statement', 'Revenue', FALSE),
        ('4110', '4110', 'Scrap Sales', FALSE, 'other-income', 'Other Income', 'Income Statement', 'Revenue', FALSE),
        ('4120', '4120', 'Foreign Exchange Gains', FALSE, 'other-income', 'Other Income', 'Income Statement', 'Revenue', FALSE),

        -- COST OF GOODS SOLD
        ('cogs', NULL, 'Cost of Goods Sold', TRUE, 'income-statement', NULL, 'Income Statement', 'Expense', FALSE),
        ('5010', '5010', 'Cost of Goods Sold - Direct', FALSE, 'cogs', 'Cost of Goods Sold', 'Income Statement', 'Expense', FALSE),
        ('5050', '5050', 'Indirect Materials & Services', FALSE, 'cogs', 'Cost of Goods Sold', 'Income Statement', 'Expense', FALSE),
        ('5060', '5060', 'Labor & Machine Absorption', FALSE, 'cogs', 'Cost of Goods Sold', 'Income Statement', 'Expense', FALSE),

        ('variances', NULL, 'Variances', TRUE, 'cogs', NULL, 'Income Statement', 'Expense', FALSE),
        ('5210', '5210', 'Purchase Price Variance', FALSE, 'variances', 'Cost of Goods Sold', 'Income Statement', 'Expense', FALSE),
        ('5220', '5220', 'Material Usage Variance', FALSE, 'variances', 'Cost of Goods Sold', 'Income Statement', 'Expense', FALSE),
        ('5230', '5230', 'Labor & Machine Variance', FALSE, 'variances', 'Cost of Goods Sold', 'Income Statement', 'Expense', FALSE),
        ('5240', '5240', 'Overhead Variance', FALSE, 'variances', 'Cost of Goods Sold', 'Income Statement', 'Expense', FALSE),
        ('5250', '5250', 'Lot Size Variance', FALSE, 'variances', 'Cost of Goods Sold', 'Income Statement', 'Expense', FALSE),
        ('5260', '5260', 'Subcontracting Variance', FALSE, 'variances', 'Cost of Goods Sold', 'Income Statement', 'Expense', FALSE),

        ('inventory-adjustments', NULL, 'Inventory Adjustments', TRUE, 'cogs', NULL, 'Income Statement', 'Expense', FALSE),
        ('5310', '5310', 'Inventory Adjustment', FALSE, 'inventory-adjustments', 'Cost of Goods Sold', 'Income Statement', 'Expense', FALSE),

        -- OPERATING EXPENSES
        ('operating-expenses', NULL, 'Operating Expenses', TRUE, 'income-statement', NULL, 'Income Statement', 'Expense', FALSE),
        ('6010', '6010', 'Maintenance Expense', FALSE, 'operating-expenses', 'Expense', 'Income Statement', 'Expense', FALSE),
        ('6020', '6020', 'Sales Commissions', FALSE, 'operating-expenses', 'Expense', 'Income Statement', 'Expense', FALSE),
        ('6030', '6030', 'Advertising & Marketing', FALSE, 'operating-expenses', 'Expense', 'Income Statement', 'Expense', FALSE),
        ('6040', '6040', 'Freight & Shipping Out', FALSE, 'operating-expenses', 'Expense', 'Income Statement', 'Expense', FALSE),
        ('6050', '6050', 'Bad Debts Expense', FALSE, 'operating-expenses', 'Expense', 'Income Statement', 'Expense', FALSE),
        ('6060', '6060', 'Salaries - Administrative', FALSE, 'operating-expenses', 'Expense', 'Income Statement', 'Expense', FALSE),
        ('6070', '6070', 'Rent & Utilities (Non-Factory)', FALSE, 'operating-expenses', 'Expense', 'Income Statement', 'Expense', FALSE),
        ('6080', '6080', 'Professional Fees', FALSE, 'operating-expenses', 'Expense', 'Income Statement', 'Expense', FALSE),
        ('6090', '6090', 'Travel & Entertainment', FALSE, 'operating-expenses', 'Expense', 'Income Statement', 'Expense', FALSE),
        ('6100', '6100', 'Insurance', FALSE, 'operating-expenses', 'Expense', 'Income Statement', 'Expense', FALSE),
        ('6110', '6110', 'Bank Charges & Fees', FALSE, 'operating-expenses', 'Expense', 'Income Statement', 'Expense', FALSE),

        ('depreciation', NULL, 'Depreciation & Amortization', TRUE, 'operating-expenses', NULL, 'Income Statement', 'Expense', FALSE),
        ('6310', '6310', 'Depreciation Expense', FALSE, 'depreciation', 'Other Expense', 'Income Statement', 'Expense', FALSE),
        ('6320', '6320', 'Gains and Losses on Disposal', FALSE, 'depreciation', 'Other Expense', 'Income Statement', 'Expense', FALSE),

        -- OTHER EXPENSES
        ('other-expenses', NULL, 'Other Expenses', TRUE, 'income-statement', NULL, 'Income Statement', 'Expense', FALSE),
        ('7010', '7010', 'Interest Expense', FALSE, 'other-expenses', 'Other Expense', 'Income Statement', 'Expense', FALSE),
        ('7020', '7020', 'Supplier Payment Discounts', FALSE, 'other-expenses', 'Other Expense', 'Income Statement', 'Expense', FALSE),
        ('7030', '7030', 'Customer Payment Discounts', FALSE, 'other-expenses', 'Other Expense', 'Income Statement', 'Expense', FALSE),
        ('7040', '7040', 'Service Charge Account', FALSE, 'other-expenses', 'Other Expense', 'Income Statement', 'Expense', FALSE),
        ('7050', '7050', 'Rounding Account', FALSE, 'other-expenses', 'Other Expense', 'Income Statement', 'Expense', FALSE),
        ('7060', '7060', 'Foreign Exchange Losses', FALSE, 'other-expenses', 'Other Expense', 'Income Statement', 'Expense', FALSE),
        ('7070', '7070', 'Income Tax Expense', FALSE, 'other-expenses', 'Other Expense', 'Income Statement', 'Expense', FALSE),
        ('7080', '7080', 'R&D Expenses', FALSE, 'other-expenses', 'Other Expense', 'Income Statement', 'Expense', FALSE)
      ) AS t(key, number, name, is_group, parent_key, account_type, income_balance, class, is_system)
    LOOP
      -- Resolve parent
      IF acc.parent_key IS NOT NULL THEN
        parent_id := key_to_id -> acc.parent_key;
      ELSE
        parent_id := NULL;
      END IF;

      -- Insert account
      INSERT INTO "account" (
        number, name, "isGroup", "accountType", "incomeBalance", class,
        "parentId", "isSystem", "companyGroupId", "createdBy"
      ) VALUES (
        acc.number,
        acc.name,
        acc.is_group,
        acc.account_type::"accountType",
        acc.income_balance::"glIncomeBalance",
        acc.class::"glAccountClass",
        parent_id,
        COALESCE(acc.is_system, false),
        cg_id,
        'system'
      ) RETURNING id INTO new_id;

      -- Track key -> id mapping
      key_to_id := key_to_id || hstore(acc.key, new_id);
    END LOOP;

    -- Insert accountDefaults for companies in this group (using account IDs from key_to_id)
    INSERT INTO "accountDefault" (
      "companyId",
      "salesAccount", "salesDiscountAccount", "costOfGoodsSoldAccount",
      "purchaseVarianceAccount", "inventoryAdjustmentVarianceAccount",
      "materialVarianceAccount", "laborAndMachineVarianceAccount",
      "overheadVarianceAccount", "lotSizeVarianceAccount", "subcontractingVarianceAccount",
      "indirectCostAccount", "maintenanceAccount", "assetDepreciationExpenseAccount",
      "assetGainsAndLossesAccount", "serviceChargeAccount", "interestAccount",
      "supplierPaymentDiscountAccount", "customerPaymentDiscountAccount", "roundingAccount",
      "assetAquisitionCostAccount", "assetAquisitionCostOnDisposalAccount",
      "accumulatedDepreciationAccount", "accumulatedDepreciationOnDisposalAccount",
      "inventoryAccount", "workInProgressAccount",
      "receivablesAccount", "bankCashAccount",
      "bankLocalCurrencyAccount", "bankForeignCurrencyAccount", "prepaymentAccount",
      "payablesAccount", "goodsReceivedNotInvoicedAccount", "inventoryShippedNotInvoicedAccount",
      "salesTaxPayableAccount", "purchaseTaxPayableAccount", "reverseChargeSalesTaxPayableAccount",
      "retainedEarningsAccount", "currencyTranslationAccount",
      "laborAbsorptionAccount"
    )
    SELECT
      c.id,
      key_to_id -> '4010', key_to_id -> '4020', key_to_id -> '5010',
      key_to_id -> '5210', key_to_id -> '5310',
      key_to_id -> '5220', key_to_id -> '5230',
      key_to_id -> '5240', key_to_id -> '5250', key_to_id -> '5260',
      key_to_id -> '5050', key_to_id -> '6010', key_to_id -> '6310',
      key_to_id -> '6320', key_to_id -> '7040', key_to_id -> '7010',
      key_to_id -> '7020', key_to_id -> '7030', key_to_id -> '7050',
      key_to_id -> '1310', key_to_id -> '1320',
      key_to_id -> '1330', key_to_id -> '1340',
      key_to_id -> '1210', key_to_id -> '1230',
      key_to_id -> '1110', key_to_id -> '1010',
      key_to_id -> '1020', key_to_id -> '1030', key_to_id -> '2110',
      key_to_id -> '2010', key_to_id -> '2125', key_to_id -> '2130',
      key_to_id -> '2210', key_to_id -> '2220', key_to_id -> '2230',
      key_to_id -> '3100', key_to_id -> '3200',
      key_to_id -> '5060'
    FROM company c
    WHERE c."companyGroupId" = cg_id;

  END LOOP;
END;
$$;


-- ============================================================
-- Phase 5: Ensure new accountDefault columns are NOT NULL
-- ============================================================

ALTER TABLE "accountDefault" ALTER COLUMN "goodsReceivedNotInvoicedAccount" SET NOT NULL;
ALTER TABLE "accountDefault" ALTER COLUMN "overheadVarianceAccount" SET NOT NULL;
ALTER TABLE "accountDefault" ALTER COLUMN "lotSizeVarianceAccount" SET NOT NULL;
ALTER TABLE "accountDefault" ALTER COLUMN "subcontractingVarianceAccount" SET NOT NULL;
ALTER TABLE "accountDefault" ALTER COLUMN "currencyTranslationAccount" SET NOT NULL;


-- ============================================================
-- Phase 6: Re-add all FK constraints
-- ============================================================

-- Self-referential
ALTER TABLE "account" ADD CONSTRAINT "account_parentId_fkey"
  FOREIGN KEY ("parentId") REFERENCES "account"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;

-- accountDefault FKs (35 columns, simple FK to account ID)
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_salesAccount_fkey"
  FOREIGN KEY ("salesAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_salesDiscountAccount_fkey"
  FOREIGN KEY ("salesDiscountAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_costOfGoodsSoldAccount_fkey"
  FOREIGN KEY ("costOfGoodsSoldAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_purchaseVarianceAccount_fkey"
  FOREIGN KEY ("purchaseVarianceAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_inventoryAdjustmentVarianceAccount_fkey"
  FOREIGN KEY ("inventoryAdjustmentVarianceAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_materialVarianceAccount_fkey"
  FOREIGN KEY ("materialVarianceAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_laborAndMachineVarianceAccount_fkey"
  FOREIGN KEY ("laborAndMachineVarianceAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_overheadVarianceAccount_fkey"
  FOREIGN KEY ("overheadVarianceAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_lotSizeVarianceAccount_fkey"
  FOREIGN KEY ("lotSizeVarianceAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_subcontractingVarianceAccount_fkey"
  FOREIGN KEY ("subcontractingVarianceAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_indirectCostAccount_fkey"
  FOREIGN KEY ("indirectCostAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
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
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_workInProgressAccount_fkey"
  FOREIGN KEY ("workInProgressAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_receivablesAccount_fkey"
  FOREIGN KEY ("receivablesAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_inventoryShippedNotInvoicedAccount_fkey"
  FOREIGN KEY ("inventoryShippedNotInvoicedAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_goodsReceivedNotInvoicedAccount_fkey"
  FOREIGN KEY ("goodsReceivedNotInvoicedAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
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
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_salesTaxPayableAccount_fkey"
  FOREIGN KEY ("salesTaxPayableAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_reverseChargeSalesTaxPayableAccount_fkey"
  FOREIGN KEY ("reverseChargeSalesTaxPayableAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_purchaseTaxPayableAccount_fkey"
  FOREIGN KEY ("purchaseTaxPayableAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_retainedEarningsAccount_fkey"
  FOREIGN KEY ("retainedEarningsAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_currencyTranslationAccount_fkey"
  FOREIGN KEY ("currencyTranslationAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "accountDefault" ADD CONSTRAINT "accountDefault_laborAbsorptionAccount_fkey"
  FOREIGN KEY ("laborAbsorptionAccount") REFERENCES "account"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- journalLine
ALTER TABLE "journalLine" ADD CONSTRAINT "journalLine_accountId_fkey"
  FOREIGN KEY ("accountId") REFERENCES "account"("id") ON UPDATE CASCADE ON DELETE SET NULL;

-- purchaseOrderLine
ALTER TABLE "purchaseOrderLine" ADD CONSTRAINT "purchaseOrderLine_accountId_fkey"
  FOREIGN KEY ("accountId") REFERENCES "account"("id") ON UPDATE CASCADE ON DELETE SET NULL;

-- salesOrderLine
ALTER TABLE "salesOrderLine" ADD CONSTRAINT "salesOrderLine_accountId_fkey"
  FOREIGN KEY ("accountId") REFERENCES "account"("id") ON UPDATE CASCADE ON DELETE SET NULL;

-- salesInvoiceLine
ALTER TABLE "salesInvoiceLine" ADD CONSTRAINT "salesInvoiceLine_accountId_fkey"
  FOREIGN KEY ("accountId") REFERENCES "account"("id") ON UPDATE CASCADE ON DELETE SET NULL;

-- purchaseInvoiceLine
ALTER TABLE "purchaseInvoiceLine" ADD CONSTRAINT "purchaseInvoiceLine_accountId_fkey"
  FOREIGN KEY ("accountId") REFERENCES "account"("id") ON UPDATE CASCADE ON DELETE SET NULL;

-- shippingMethod
ALTER TABLE "shippingMethod" ADD CONSTRAINT "shippingMethod_carrierAccountId_fkey"
  FOREIGN KEY ("carrierAccountId") REFERENCES "account"("id") ON UPDATE CASCADE ON DELETE SET NULL;
