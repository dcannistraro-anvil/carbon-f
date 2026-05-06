-- Remove remaining posting-group interceptors after posting group tables are dropped.
-- The interceptor migrations that introduced these functions are on main, so keep
-- the correction in a new migration instead of editing historical SQL.

-- Preserve customer type group synchronization, but stop invoking the posting
-- group sync function that inserts into the removed postingGroupSales table.
SELECT attach_event_trigger(
  'customerType',
  ARRAY['sync_update_customer_type_group_name']::TEXT[],
  ARRAY['sync_create_customer_type_group']::TEXT[]
);

DROP FUNCTION IF EXISTS sync_create_posting_groups_for_customer_type(TEXT, TEXT, JSONB, JSONB) CASCADE;

-- Preserve supplier type group synchronization, but stop invoking the posting
-- group sync function that inserts into the removed postingGroupPurchasing table.
SELECT attach_event_trigger(
  'supplierType',
  ARRAY['sync_update_supplier_type_group_name']::TEXT[],
  ARRAY['sync_create_supplier_type_group']::TEXT[]
);

DROP FUNCTION IF EXISTS sync_create_posting_groups_for_supplier_type(TEXT, TEXT, JSONB, JSONB) CASCADE;
