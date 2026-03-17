DROP VIEW IF EXISTS "issues";
CREATE OR REPLACE VIEW "issues" WITH(SECURITY_INVOKER=true) AS
  SELECT
    ncr.*,
    nci."items",
    CASE
      WHEN EXISTS (
        SELECT 1 FROM "nonConformanceActionTask" ncat
        JOIN "nonConformanceRequiredAction" ncra ON ncat."actionTypeId" = ncra.id
        WHERE ncat."nonConformanceId" = ncr.id
          AND ncra."systemType" = 'Containment'
          AND ncat.status IN ('In Progress', 'Completed')
      ) THEN 'Contained'
      WHEN EXISTS (
        SELECT 1 FROM "nonConformanceActionTask" ncat
        JOIN "nonConformanceRequiredAction" ncra ON ncat."actionTypeId" = ncra.id
        WHERE ncat."nonConformanceId" = ncr.id
          AND ncra."systemType" = 'Containment'
      ) THEN 'Uncontained'
      ELSE 'N/A'
    END AS "containmentStatus"
  FROM "nonConformance" ncr
  LEFT JOIN (
    SELECT "nonConformanceId", array_agg("itemId"::text) as items
    FROM "nonConformanceItem"
    GROUP BY "nonConformanceId"
  ) nci ON nci."nonConformanceId" = ncr."id";
