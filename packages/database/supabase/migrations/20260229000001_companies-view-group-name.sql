-- Add companyGroupName to the companies view
DROP VIEW IF EXISTS "companies";
CREATE OR REPLACE VIEW "companies" WITH(SECURITY_INVOKER=true) AS
  SELECT DISTINCT
    c.*,
    uc.*,
    et.name AS "employeeType",
    cg.name AS "companyGroupName"
    FROM "userToCompany" uc
    INNER JOIN "company" c
      ON c.id = uc."companyId"
    LEFT JOIN "employee" e
      ON e.id = uc."userId" AND e."companyId" = uc."companyId"
    LEFT JOIN "employeeType" et
      ON et.id = e."employeeTypeId"
    LEFT JOIN "companyGroup" cg
      ON cg.id = c."companyGroupId";
