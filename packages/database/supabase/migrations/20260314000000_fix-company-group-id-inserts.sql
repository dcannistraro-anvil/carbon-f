-- Fix: Trigger functions were missing companyGroupId in their INSERT statements.
-- After the company-groups migration added NOT NULL companyGroupId columns to
-- posting group tables and itemUnitSalePrice, these triggers would fail.

-- 1. Fix create_item_related_records (item trigger)
CREATE OR REPLACE FUNCTION public.create_item_related_records()
RETURNS TRIGGER AS $$
DECLARE
  base_currency TEXT;
BEGIN
  SELECT "baseCurrencyCode"
  INTO base_currency
  FROM public."company"
  WHERE "id" = new."companyId";

  INSERT INTO public."itemCost"("itemId", "costingMethod", "createdBy", "companyId")
  VALUES (new.id, 'FIFO', new."createdBy", new."companyId");

  INSERT INTO public."itemReplenishment"("itemId", "createdBy", "companyId")
  VALUES (new.id, new."createdBy", new."companyId");

  INSERT INTO public."itemUnitSalePrice"("itemId", "currencyCode", "createdBy", "companyId")
  VALUES (new.id, COALESCE(base_currency, 'USD'), new."createdBy", new."companyId");

  -- Insert itemPlanning records for each location
  INSERT INTO public."itemPlanning"("itemId", "locationId", "createdBy", "companyId")
  SELECT
    new.id,
    l.id,
    new."createdBy",
    new."companyId"
  FROM public."location" l
  WHERE l."companyId" = new."companyId";

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 2. Fix create_related_records_for_location (location trigger)
-- Posting group tables were dropped; only itemPlanning logic remains.
CREATE OR REPLACE FUNCTION public.create_related_records_for_location()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public."itemPlanning" ("itemId", "locationId", "createdBy", "companyId", "createdAt", "updatedAt")
  SELECT
    i.id AS "itemId",
    new.id AS "locationId",
    i."createdBy",
    i."companyId",
    NOW(),
    NOW()
  FROM public."item" i
  WHERE i."companyId" = new."companyId";

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
