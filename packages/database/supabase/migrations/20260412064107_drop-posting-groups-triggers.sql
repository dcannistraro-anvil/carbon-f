-- Drop the problematic triggers that reference the removed postingGroupInventory table
-- These were incorrectly added in migration 20260410031811_remaining-interceptors.sql 
-- after the posting groups tables were already dropped in 20260229000000_drop-posting-groups.sql

-- Drop the trigger that tries to insert into postingGroupInventory when a location is created
DROP FUNCTION IF EXISTS sync_create_location_related_records CASCADE;

-- Create a fixed version without the postingGroupInventory inserts
CREATE OR REPLACE FUNCTION sync_create_location_related_records(
  p_table TEXT, p_operation TEXT, p_new JSONB, p_old JSONB
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF p_operation != 'INSERT' THEN RETURN; END IF;

  -- Only create itemPlanning records for the new location
  -- Skip the postingGroupInventory inserts since that table no longer exists
  INSERT INTO "itemPlanning" ("itemId", "locationId", "createdBy", "companyId", "createdAt", "updatedAt")
  SELECT
    i.id AS "itemId",
    p_new->>'id' AS "locationId",
    i."createdBy",
    i."companyId",
    NOW(),
    NOW()
  FROM "item" i
  WHERE i."companyId" = p_new->>'companyId';
END;
$$;

-- Detach itemPostingGroup AFTER-row interceptor (interceptors live on triggers via
-- attach_event_trigger, not in a registry table).
SELECT attach_event_trigger('itemPostingGroup', ARRAY[]::TEXT[], ARRAY[]::TEXT[]);

DROP FUNCTION IF EXISTS sync_create_posting_groups_for_item_posting_group CASCADE;