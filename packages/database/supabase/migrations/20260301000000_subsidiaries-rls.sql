-- Allow users to see all companies in their company groups
-- The existing SELECT policy only shows companies the user is a member of.
-- This policy extends visibility to sibling companies in the same group.
DROP POLICY IF EXISTS "SELECT" ON "company";
CREATE POLICY "SELECT" ON "company"
FOR SELECT USING (
  "companyGroupId" IS NOT NULL AND
  "companyGroupId" = ANY(
    (SELECT get_company_groups_for_employee())::text[]
  )
);
