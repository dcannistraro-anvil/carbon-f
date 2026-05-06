-- Allow authenticated users to read company groups they belong to
CREATE POLICY "SELECT" ON "companyGroup"
FOR SELECT USING (
  "id" IN (
    SELECT "companyGroupId" FROM "company"
    WHERE "id" = ANY (
      SELECT "companyId" FROM "userToCompany"
      WHERE "userId" = auth.uid()::text
    )
  )
);
