-- Add operationDueDate to job operation functions

-- 1. get_active_job_operations_by_location
DROP FUNCTION IF EXISTS get_active_job_operations_by_location;
CREATE OR REPLACE FUNCTION get_active_job_operations_by_location(
  location_id TEXT,
  work_center_ids TEXT[]
)
RETURNS TABLE (
  "id" TEXT,
  "jobId" TEXT,
  "jobMakeMethodId" TEXT,
  "operationOrder" DOUBLE PRECISION,
  "priority" DOUBLE PRECISION,
  "processId" TEXT,
  "workCenterId" TEXT,
  "description" TEXT,
  "setupTime" NUMERIC,
  "setupUnit" factor,
  "laborTime" NUMERIC,
  "laborUnit" factor,
  "machineTime" NUMERIC,
  "machineUnit" factor,
  "operationOrderType" "methodOperationOrder",
  "jobReadableId" TEXT,
  "jobStatus" "jobStatus",
  "jobDueDate" DATE,
  "jobDeadlineType" "deadlineType",
  "jobCustomerId" TEXT,
  "customerName" TEXT,
  "parentMaterialId" TEXT,
  "itemReadableId" TEXT,
  "itemDescription" TEXT,
  "operationStatus" "jobOperationStatus",
  "targetQuantity" NUMERIC,
  "operationQuantity" NUMERIC,
  "quantityComplete" NUMERIC,
  "quantityScrapped" NUMERIC,
  "salesOrderId" TEXT,
  "salesOrderLineId" TEXT,
  "salesOrderReadableId" TEXT,
  "assignee" TEXT,
  "tags" TEXT[],
  "thumbnailPath" TEXT,
  "operationDueDate" DATE
)
SECURITY INVOKER
AS $$
BEGIN
  RETURN QUERY
  WITH relevant_jobs AS (
    SELECT *
    FROM "job"
    WHERE "locationId" = location_id
    AND ("status" = 'Ready' OR "status" = 'In Progress' OR "status" = 'Paused')
  )
  SELECT
    jo."id",
    jo."jobId",
    jo."jobMakeMethodId",
    jo."order" AS "operationOrder",
    jo."priority",
    jo."processId",
    jo."workCenterId",
    jo."description",
    jo."setupTime",
    jo."setupUnit",
    jo."laborTime",
    jo."laborUnit",
    jo."machineTime",
    jo."machineUnit",
    jo."operationOrder" AS "operationOrderType",
    rj."jobId" AS "jobReadableId",
    rj."status" AS "jobStatus",
    rj."dueDate" AS "jobDueDate",
    rj."deadlineType" AS "jobDeadlineType",
    rj."customerId" AS "jobCustomerId",
    c."name" AS "customerName",
    jmm."parentMaterialId",
    i."readableId" as "itemReadableId",
    i."name" as "itemDescription",
    CASE
      WHEN rj."status" = 'Paused' THEN 'Paused'
      ELSE jo."status"
    END AS "operationStatus",
    jo."targetQuantity"::NUMERIC,
    jo."operationQuantity",
    jo."quantityComplete",
    jo."quantityScrapped",
    rj."salesOrderId",
    rj."salesOrderLineId",
    so."salesOrderId" as "salesOrderReadableId",
    jo."assignee",
    jo."tags",
    COALESCE(mu."thumbnailPath", i."thumbnailPath") as "thumbnailPath",
    jo."dueDate" AS "operationDueDate"
  FROM "jobOperation" jo
  JOIN relevant_jobs rj ON rj.id = jo."jobId"
  LEFT JOIN "jobMakeMethod" jmm ON jo."jobMakeMethodId" = jmm.id
  LEFT JOIN "item" i ON jmm."itemId" = i.id
  LEFT JOIN "customer" c ON rj."customerId" = c.id
  LEFT JOIN "salesOrder" so ON rj."salesOrderId" = so.id
  LEFT JOIN "modelUpload" mu ON i."modelUploadId" = mu.id
   WHERE CASE
    WHEN array_length(work_center_ids, 1) > 0 THEN
      jo."workCenterId" = ANY(work_center_ids) AND jo."status" != 'Done' AND jo."status" != 'Canceled'
    ELSE jo."status" != 'Done' AND jo."status" != 'Canceled'
  END
  ORDER BY jo."startDate", jo."priority";

END;
$$ LANGUAGE plpgsql;


-- 2. get_job_operation_by_id
DROP FUNCTION IF EXISTS get_job_operation_by_id(TEXT);
CREATE OR REPLACE FUNCTION get_job_operation_by_id(operation_id TEXT)
RETURNS TABLE (
  id TEXT,
  "jobId" TEXT,
  "jobMakeMethodId" TEXT,
  "operationOrder" DOUBLE PRECISION,
  "processId" TEXT,
  "workCenterId" TEXT,
  description TEXT,
  "setupTime" NUMERIC,
  "setupUnit" factor,
  "laborTime" NUMERIC,
  "laborUnit" factor,
  "machineTime" NUMERIC,
  "machineUnit" factor,
  "operationOrderType" "methodOperationOrder",
  "jobReadableId" TEXT,
  "jobStatus" "jobStatus",
  "jobDueDate" DATE,
  "jobDeadlineType" "deadlineType",
  "parentMaterialId" TEXT,
  "itemId" TEXT,
  "itemReadableId" TEXT,
  "itemDescription" TEXT,
  "itemUnitOfMeasure" TEXT,
  "itemModelPath" TEXT,
  "itemModelId" TEXT,
  "itemModelName" TEXT,
  "itemModelSize" BIGINT,
  "operationStatus" "jobOperationStatus",
  "targetQuantity" NUMERIC,
  "operationQuantity" NUMERIC,
  "quantityComplete" NUMERIC,
  "quantityReworked" NUMERIC,
  "quantityScrapped" NUMERIC,
  "workInstruction" JSON,
  "operationDueDate" DATE
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    jo."id",
    jo."jobId",
    jo."jobMakeMethodId",
    jo."order" AS "operationOrder",
    jo."processId",
    jo."workCenterId",
    jo."description",
    jo."setupTime",
    jo."setupUnit",
    jo."laborTime",
    jo."laborUnit",
    jo."machineTime",
    jo."machineUnit",
    jo."operationOrder" AS "operationOrderType",
    j."jobId" AS "jobReadableId",
    j."status" AS "jobStatus",
    j."dueDate"::DATE AS "jobDueDate",
    j."deadlineType" AS "jobDeadlineType",
    jmm."parentMaterialId",
    i."id" as "itemId",
    i."readableIdWithRevision" as "itemReadableId",
    i."name" as "itemDescription",
    uom."name" as "itemUnitOfMeasure",
    m."modelPath" as "itemModelPath",
    m."id" as "itemModelId",
    m."name" as "itemModelName",
    m."size" as "itemModelSize",
    jo."status" AS "operationStatus",
    jo."targetQuantity"::NUMERIC,
    jo."operationQuantity",
    jo."quantityComplete",
    jo."quantityReworked",
    jo."quantityScrapped",
    jo."workInstruction",
    jo."dueDate" AS "operationDueDate"
  FROM "jobOperation" jo
  JOIN "job" j ON j.id = jo."jobId"
  LEFT JOIN "jobMakeMethod" jmm ON jo."jobMakeMethodId" = jmm.id
  LEFT JOIN "item" i ON jmm."itemId" = i.id
  LEFT JOIN "unitOfMeasure" uom ON i."unitOfMeasureCode" = uom."code" AND i."companyId" = uom."companyId"
  LEFT JOIN "modelUpload" m ON i."modelUploadId" = m.id
  WHERE jo.id = operation_id
  LIMIT 1;
END;
$$ LANGUAGE plpgsql;


-- 3. get_active_job_operations_by_employee
DROP FUNCTION IF EXISTS get_active_job_operations_by_employee;
CREATE OR REPLACE FUNCTION get_active_job_operations_by_employee(
  employee_id TEXT,
  company_id TEXT
)
RETURNS TABLE (
  "id" TEXT,
  "jobId" TEXT,
  "operationOrder" DOUBLE PRECISION,
  "processId" TEXT,
  "workCenterId" TEXT,
  "description" TEXT,
  "setupTime" NUMERIC,
  "setupUnit" factor,
  "laborTime" NUMERIC,
  "laborUnit" factor,
  "machineTime" NUMERIC,
  "machineUnit" factor,
  "operationOrderType" "methodOperationOrder",
  "jobReadableId" TEXT,
  "jobStatus" "jobStatus",
  "jobDueDate" DATE,
  "jobDeadlineType" "deadlineType",
  "jobCustomerId" TEXT,
  "salesOrderReadableId" TEXT,
  "salesOrderId" TEXT,
  "salesOrderLineId" TEXT,
  "parentMaterialId" TEXT,
  "itemReadableId" TEXT,
  "itemDescription" TEXT,
  "operationStatus" "jobOperationStatus",
  "targetQuantity" NUMERIC,
  "operationQuantity" NUMERIC,
  "quantityComplete" NUMERIC,
  "quantityScrapped" NUMERIC,
  "thumbnailPath" TEXT,
  "assignee" TEXT,
  "tags" TEXT[],
  "operationDueDate" DATE
)
SECURITY INVOKER
AS $$
BEGIN
  RETURN QUERY
  WITH active_production_events AS (
    SELECT DISTINCT "jobOperationId"
    FROM "productionEvent"
    WHERE "employeeId" = employee_id AND "endTime" IS NULL AND "companyId" = company_id
  )
  SELECT
    jo."id",
    jo."jobId",
    jo."order" AS "operationOrder",
    jo."processId",
    jo."workCenterId",
    jo."description",
    jo."setupTime",
    jo."setupUnit",
    jo."laborTime",
    jo."laborUnit",
    jo."machineTime",
    jo."machineUnit",
    jo."operationOrder" AS "operationOrderType",
    j."jobId" AS "jobReadableId",
    j."status" AS "jobStatus",
    j."dueDate" AS "jobDueDate",
    j."deadlineType" AS "jobDeadlineType",
    j."customerId" AS "jobCustomerId",
    so."salesOrderId" AS "salesOrderReadableId",
    so."id" AS "salesOrderId",
    j."salesOrderLineId",
    jmm."parentMaterialId",
    i."readableId" as "itemReadableId",
    i."name" as "itemDescription",
    jo."status" AS "operationStatus",
    jo."targetQuantity"::NUMERIC,
    jo."operationQuantity",
    jo."quantityComplete",
    jo."quantityScrapped",
    CASE
      WHEN jmm."parentMaterialId" IS NULL THEN COALESCE(i."thumbnailPath", j_mu."thumbnailPath", i_mu."thumbnailPath")
      ELSE COALESCE(i."thumbnailPath", i_mu."thumbnailPath")
    END as "thumbnailPath",
    jo."assignee",
    jo."tags",
    jo."dueDate" AS "operationDueDate"
  FROM "jobOperation" jo
  JOIN "job" j ON j.id = jo."jobId"
  LEFT JOIN "salesOrderLine" sol ON sol."id" = j."salesOrderLineId"
  LEFT JOIN "salesOrder" so ON so."id" = sol."salesOrderId"
  LEFT JOIN "jobMakeMethod" jmm ON jo."jobMakeMethodId" = jmm.id
  LEFT JOIN "item" i ON jmm."itemId" = i.id
  LEFT JOIN "modelUpload" j_mu ON j_mu.id = j."modelUploadId"
  LEFT JOIN "modelUpload" i_mu ON i_mu.id = i."modelUploadId"
  JOIN active_production_events ape ON ape."jobOperationId" = jo.id;
END;
$$ LANGUAGE plpgsql;


-- 4. get_recent_job_operations_by_employee
DROP FUNCTION IF EXISTS get_recent_job_operations_by_employee;
CREATE OR REPLACE FUNCTION get_recent_job_operations_by_employee(
  employee_id TEXT,
  company_id TEXT
)
RETURNS TABLE (
  "id" TEXT,
  "jobId" TEXT,
  "operationOrder" DOUBLE PRECISION,
  "processId" TEXT,
  "workCenterId" TEXT,
  "description" TEXT,
  "setupTime" NUMERIC,
  "setupUnit" factor,
  "laborTime" NUMERIC,
  "laborUnit" factor,
  "machineTime" NUMERIC,
  "machineUnit" factor,
  "operationOrderType" "methodOperationOrder",
  "jobReadableId" TEXT,
  "jobStatus" "jobStatus",
  "jobDueDate" DATE,
  "jobDeadlineType" "deadlineType",
  "jobCustomerId" TEXT,
  "salesOrderReadableId" TEXT,
  "salesOrderId" TEXT,
  "salesOrderLineId" TEXT,
  "parentMaterialId" TEXT,
  "itemReadableId" TEXT,
  "itemDescription" TEXT,
  "operationStatus" "jobOperationStatus",
  "targetQuantity" NUMERIC,
  "operationQuantity" NUMERIC,
  "quantityComplete" NUMERIC,
  "quantityScrapped" NUMERIC,
  "thumbnailPath" TEXT,
  "assignee" TEXT,
  "tags" TEXT[],
  "operationDueDate" DATE
)
SECURITY INVOKER
AS $$
BEGIN
  RETURN QUERY
  WITH recent_production_events AS (
    SELECT "jobOperationId", MAX("endTime") as "lastActivity"
    FROM "productionEvent"
    WHERE "employeeId" = employee_id AND "companyId" = company_id
    GROUP BY "jobOperationId"
    ORDER BY MAX("endTime") DESC
    LIMIT 20
  ),
  recent_production_quantities AS (
    SELECT "jobOperationId", MAX("createdAt") as "lastActivity"
    FROM "productionQuantity"
    WHERE "createdBy" = employee_id AND "companyId" = company_id
    GROUP BY "jobOperationId"
    ORDER BY MAX("createdAt") DESC
    LIMIT 20
  ),
  combined_recent_activities AS (
    SELECT DISTINCT ON ("jobOperationId") "jobOperationId", "lastActivity"
    FROM (
      SELECT "jobOperationId", "lastActivity"
      FROM recent_production_events
      UNION ALL
      SELECT "jobOperationId", "lastActivity"
      FROM recent_production_quantities
    ) combined
    ORDER BY "jobOperationId", "lastActivity" DESC
  )
  SELECT
    jo."id",
    jo."jobId",
    jo."order" AS "operationOrder",
    jo."processId",
    jo."workCenterId",
    jo."description",
    jo."setupTime",
    jo."setupUnit",
    jo."laborTime",
    jo."laborUnit",
    jo."machineTime",
    jo."machineUnit",
    jo."operationOrder" AS "operationOrderType",
    j."jobId" AS "jobReadableId",
    j."status" AS "jobStatus",
    j."dueDate" AS "jobDueDate",
    j."deadlineType" AS "jobDeadlineType",
    j."customerId" AS "jobCustomerId",
    so."salesOrderId" AS "salesOrderReadableId",
    so."id" AS "salesOrderId",
    j."salesOrderLineId",
    jmm."parentMaterialId",
    i."readableId" as "itemReadableId",
    i."name" as "itemDescription",
    jo."status" AS "operationStatus",
    jo."targetQuantity"::NUMERIC,
    jo."operationQuantity",
    jo."quantityComplete",
    jo."quantityScrapped",
    CASE
      WHEN jmm."parentMaterialId" IS NULL THEN COALESCE(i."thumbnailPath", j_mu."thumbnailPath", i_mu."thumbnailPath")
      ELSE COALESCE(i."thumbnailPath", i_mu."thumbnailPath")
    END as "thumbnailPath",
    jo."assignee",
    jo."tags",
    jo."dueDate" AS "operationDueDate"
  FROM combined_recent_activities cra
  JOIN "jobOperation" jo ON jo.id = cra."jobOperationId"
  JOIN "job" j ON j.id = jo."jobId"
  LEFT JOIN "salesOrderLine" sol ON sol."id" = j."salesOrderLineId"
  LEFT JOIN "salesOrder" so ON so."id" = sol."salesOrderId"
  LEFT JOIN "jobMakeMethod" jmm ON jo."jobMakeMethodId" = jmm.id
  LEFT JOIN "item" i ON jmm."itemId" = i.id
  LEFT JOIN "modelUpload" j_mu ON j_mu.id = j."modelUploadId"
  LEFT JOIN "modelUpload" i_mu ON i_mu.id = i."modelUploadId"
  ORDER BY cra."lastActivity" DESC
  LIMIT 20;
END;
$$ LANGUAGE plpgsql;


-- 5. get_assigned_job_operations
DROP FUNCTION IF EXISTS get_assigned_job_operations;
CREATE OR REPLACE FUNCTION get_assigned_job_operations(
  user_id TEXT,
  company_id TEXT
)
RETURNS TABLE (
  "id" TEXT,
  "jobId" TEXT,
  "operationOrder" DOUBLE PRECISION,
  "processId" TEXT,
  "workCenterId" TEXT,
  "description" TEXT,
  "setupTime" NUMERIC,
  "setupUnit" factor,
  "laborTime" NUMERIC,
  "laborUnit" factor,
  "machineTime" NUMERIC,
  "machineUnit" factor,
  "operationOrderType" "methodOperationOrder",
  "jobReadableId" TEXT,
  "jobStatus" "jobStatus",
  "jobDueDate" DATE,
  "jobDeadlineType" "deadlineType",
  "jobCustomerId" TEXT,
  "salesOrderReadableId" TEXT,
  "salesOrderId" TEXT,
  "salesOrderLineId" TEXT,
  "parentMaterialId" TEXT,
  "itemReadableId" TEXT,
  "itemDescription" TEXT,
  "operationStatus" "jobOperationStatus",
  "targetQuantity" NUMERIC,
  "operationQuantity" NUMERIC,
  "quantityComplete" NUMERIC,
  "quantityScrapped" NUMERIC,
  "thumbnailPath" TEXT,
  "assignee" TEXT,
  "tags" TEXT[],
  "operationDueDate" DATE
)
SECURITY INVOKER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    jo."id",
    jo."jobId",
    jo."order" AS "operationOrder",
    jo."processId",
    jo."workCenterId",
    jo."description",
    jo."setupTime",
    jo."setupUnit",
    jo."laborTime",
    jo."laborUnit",
    jo."machineTime",
    jo."machineUnit",
    jo."operationOrder" AS "operationOrderType",
    j."jobId" AS "jobReadableId",
    j."status" AS "jobStatus",
    j."dueDate" AS "jobDueDate",
    j."deadlineType" AS "jobDeadlineType",
    j."customerId" AS "jobCustomerId",
    so."salesOrderId" AS "salesOrderReadableId",
    so."id" AS "salesOrderId",
    j."salesOrderLineId",
    jmm."parentMaterialId",
    i."readableId" as "itemReadableId",
    i."name" as "itemDescription",
    CASE
      WHEN j."status" = 'Paused' THEN 'Paused'
      ELSE jo."status"
    END AS "operationStatus",
    jo."targetQuantity"::NUMERIC,
    jo."operationQuantity",
    jo."quantityComplete",
    jo."quantityScrapped",
    CASE
      WHEN jmm."parentMaterialId" IS NULL THEN COALESCE(i."thumbnailPath", j_mu."thumbnailPath", i_mu."thumbnailPath")
      ELSE COALESCE(i."thumbnailPath", i_mu."thumbnailPath")
    END as "thumbnailPath",
    jo."assignee",
    jo."tags",
    jo."dueDate" AS "operationDueDate"
  FROM "jobOperation" jo
  JOIN "job" j ON j.id = jo."jobId"
  LEFT JOIN "salesOrderLine" sol ON sol."id" = j."salesOrderLineId"
  LEFT JOIN "salesOrder" so ON so."id" = sol."salesOrderId"
  LEFT JOIN "jobMakeMethod" jmm ON jo."jobMakeMethodId" = jmm.id
  LEFT JOIN "item" i ON jmm."itemId" = i.id
  LEFT JOIN "modelUpload" j_mu ON j_mu.id = j."modelUploadId"
  LEFT JOIN "modelUpload" i_mu ON i_mu.id = i."modelUploadId"
  WHERE jo."assignee" = user_id
  AND jo."status" IN ('Todo', 'Ready', 'Waiting', 'In Progress', 'Paused')
  AND j."status" IN ('Ready', 'In Progress', 'Paused')
  AND j."companyId" = company_id
  ORDER BY jo."priority";
END;
$$ LANGUAGE plpgsql;
