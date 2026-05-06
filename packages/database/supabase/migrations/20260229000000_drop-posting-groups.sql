-- Drop triggers first
DROP TRIGGER IF EXISTS "create_location" ON "location";
DROP TRIGGER IF EXISTS "create_item_posting_group" ON "itemPostingGroup";
DROP TRIGGER IF EXISTS "create_posting_groups_for_customer_type" ON "customerType";
DROP TRIGGER IF EXISTS "create_posting_groups_for_supplier_type" ON "supplierType";

-- Drop trigger functions
DROP FUNCTION IF EXISTS "create_posting_groups_for_location"();
DROP FUNCTION IF EXISTS "create_posting_groups_for_item_posting_group"();
DROP FUNCTION IF EXISTS "create_posting_groups_for_customer_type"();
DROP FUNCTION IF EXISTS "create_posting_groups_for_supplier_type"();

-- Drop tables (CASCADE drops policies, indexes, constraints automatically)
DROP TABLE IF EXISTS "postingGroupInventory" CASCADE;
DROP TABLE IF EXISTS "postingGroupPurchasing" CASCADE;
DROP TABLE IF EXISTS "postingGroupSales" CASCADE;
