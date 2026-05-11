-- Unify MTO and MTS job completion: both now call complete_job_to_inventory.
-- Previously, MTO jobs only called backflush_job_materials(), skipping
-- cost layer creation. This meant shipment posting had no cost layers
-- to consume for COGS.

CREATE OR REPLACE FUNCTION sync_finish_job_operation(
  p_new JSONB,
  p_old JSONB,
  p_operation TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job_location_id TEXT;
  v_job_storage_unit_id TEXT;
  v_job_quantity NUMERIC;
  v_sales_order_id TEXT;
  v_quantity_complete NUMERIC;
  v_job_status TEXT;
BEGIN
  IF p_operation != 'UPDATE' THEN RETURN; END IF;
  IF (p_new->>'status') != 'Done' OR (p_old->>'status') = 'Done' THEN RETURN; END IF;

  -- Close all open production events for this operation
  UPDATE "productionEvent"
  SET "endTime" = NOW()
  WHERE "jobOperationId" = p_new->>'id'
    AND "endTime" IS NULL;

  -- Unlock dependent operations whose dependencies are now all done
  UPDATE "jobOperation" op
  SET status = 'Ready'
  WHERE EXISTS (
    SELECT 1
    FROM "jobOperationDependency" dep
    WHERE dep."operationId" = op.id
      AND dep."dependsOnId" = p_new->>'id'
      AND op.status = 'Waiting'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM "jobOperationDependency" dep2
    JOIN "jobOperation" jo2 ON jo2.id = dep2."dependsOnId"
    WHERE dep2."operationId" = op.id
      AND jo2.status != 'Done'
      AND jo2.id != p_new->>'id'
  );

  -- Only complete the job if it is in an active state (has been released/started)
  SELECT status INTO v_job_status FROM "job" WHERE id = p_new->>'jobId';
  IF v_job_status NOT IN ('Ready', 'In Progress', 'Paused') THEN
    RETURN;
  END IF;

  -- If this is the last operation, mark the job as Completed
  IF is_last_job_operation(p_new->>'id') THEN
    SELECT "locationId", "storageUnitId", quantity, "salesOrderId"
    INTO v_job_location_id, v_job_storage_unit_id, v_job_quantity, v_sales_order_id
    FROM "job"
    WHERE id = p_new->>'jobId';

    v_quantity_complete := CASE
      WHEN COALESCE((p_new->>'quantityComplete')::NUMERIC, 0) = 0 THEN v_job_quantity
      ELSE (p_new->>'quantityComplete')::NUMERIC
    END;

    PERFORM complete_job_to_inventory(
      p_job_id := p_new->>'jobId',
      p_quantity_complete := v_quantity_complete,
      p_storage_unit_id := v_job_storage_unit_id,
      p_location_id := v_job_location_id,
      p_company_id := p_new->>'companyId',
      p_user_id := p_new->>'updatedBy'
    );
  END IF;
END;
$$;
