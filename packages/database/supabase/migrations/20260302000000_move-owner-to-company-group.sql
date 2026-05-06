-- Move ownerId from company to companyGroup

-- Add ownerId to companyGroup
ALTER TABLE "companyGroup" ADD COLUMN "ownerId" TEXT REFERENCES "user"("id");

-- Backfill: for each group, take ownerId from the root company (no parentCompanyId)
UPDATE "companyGroup" cg
SET "ownerId" = (
  SELECT c."ownerId" FROM "company" c
  WHERE c."companyGroupId" = cg.id
    AND c."parentCompanyId" IS NULL
    AND c."ownerId" IN (SELECT id FROM "user")
  LIMIT 1
);

-- Drop the view first (it depends on company.ownerId)
DROP VIEW IF EXISTS "companies";

-- Drop ownerId from company
ALTER TABLE "company" DROP COLUMN "ownerId";

-- Recreate the companies view to pull ownerId from companyGroup
DROP VIEW IF EXISTS "companies";
CREATE OR REPLACE VIEW "companies" WITH(SECURITY_INVOKER=true) AS
  SELECT DISTINCT
    c.*,
    uc.*,
    et.name AS "employeeType",
    cg.name AS "companyGroupName",
    cg."ownerId"
  FROM "userToCompany" uc
  INNER JOIN "company" c
    ON c.id = uc."companyId"
  LEFT JOIN "employee" e
    ON e.id = uc."userId" AND e."companyId" = uc."companyId"
  LEFT JOIN "employeeType" et
    ON et.id = e."employeeTypeId"
  LEFT JOIN "companyGroup" cg
    ON cg.id = c."companyGroupId";
