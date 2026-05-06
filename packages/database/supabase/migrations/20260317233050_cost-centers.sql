CREATE TABLE "costCenter" (
  "id" TEXT NOT NULL DEFAULT xid(),
  "name" TEXT NOT NULL,
  "parentCostCenterId" TEXT,
  "companyId" TEXT NOT NULL,
  "createdBy" TEXT NOT NULL,
  "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  "updatedBy" TEXT,
  "updatedAt" TIMESTAMP WITH TIME ZONE,
  "customFields" JSONB,

  CONSTRAINT "costCenter_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "costCenter_parentCostCenterId_fkey" FOREIGN KEY ("parentCostCenterId") REFERENCES "costCenter"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "costCenter_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "company"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "costCenter_createdBy_fkey" FOREIGN KEY ("createdBy") REFERENCES "user"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "costCenter_updatedBy_fkey" FOREIGN KEY ("updatedBy") REFERENCES "user"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "costCenter_name_companyId_key" UNIQUE ("name", "companyId")
);

CREATE INDEX "costCenter_companyId_idx" ON "costCenter"("companyId");

ALTER TABLE "costCenter" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "SELECT" ON "public"."costCenter"
  FOR SELECT USING (
    "companyId" = ANY (
      (SELECT get_companies_with_employee_role())::text[]
    )
  );

CREATE POLICY "INSERT" ON "public"."costCenter"
  FOR INSERT WITH CHECK (
    "companyId" = ANY (
      (SELECT get_companies_with_employee_permission('accounting_create'))::text[]
    )
  );

CREATE POLICY "UPDATE" ON "public"."costCenter"
  FOR UPDATE USING (
    "companyId" = ANY (
      (SELECT get_companies_with_employee_permission('accounting_update'))::text[]
    )
  );

CREATE POLICY "DELETE" ON "public"."costCenter"
  FOR DELETE USING (
    "companyId" = ANY (
      (SELECT get_companies_with_employee_permission('accounting_delete'))::text[]
    )
  );
