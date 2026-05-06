# Database Migration Patterns Analysis

This document analyzes common patterns found in the Carbon database migrations.

To create a database migration use `npm run db:migrate:new <name>`.

- Migrations are stored in `/packages/database/supabase/migrations/`
- Named with timestamps and descriptive names
- Applied automatically via Supabase CLI

## 1. Table Creation Patterns

### Basic Table Structure

Most tables follow this pattern:

```sql
CREATE TABLE "tableName" (
  "id" TEXT NOT NULL DEFAULT id('tbl'),
  -- other columns
  "companyId" TEXT NOT NULL,
  "createdBy" TEXT NOT NULL,
  "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  "updatedBy" TEXT,
  "updatedAt" TIMESTAMP WITH TIME ZONE,

  CONSTRAINT "tableName_pkey" PRIMARY KEY ("id", "companyId"),
  CONSTRAINT "tableName_companyId_fkey" FOREIGN KEY ("companyId") REFERENCES "company"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "tableName_createdBy_fkey" FOREIGN KEY ("createdBy") REFERENCES "user"("id"),
  CONSTRAINT "tableName_updatedBy_fkey" FOREIGN KEY ("updatedBy") REFERENCES "user"("id")
);
```

## 2. ID Generation

### ID Function

- Primary keys use `TEXT NOT NULL DEFAULT id()` for globally unique IDs
- The `id()` function accepts an optional prefix parameter: `id('prefix')`
- Without a prefix, generates 20-character ordered IDs
- With a prefix, generates IDs in format: `prefix_<random>`
- Common prefixes include table abbreviations like `id('usr')`, `id('cmp')`, `id('inv')`

### Composite Primary Keys

- Many tables use composite primary keys: `PRIMARY KEY ("id", "companyId")`
- This enforces multi-tenancy at the database level

## 3. Company-Based Multi-Tenancy

### CompanyId Pattern

- Almost all business tables include `"companyId" TEXT NOT NULL`
- Foreign key to company table with CASCADE delete: `FOREIGN KEY ("companyId") REFERENCES "company"("id") ON DELETE CASCADE`
- CompanyId is often part of the primary key for tenant isolation
- Index on companyId: `CREATE INDEX "tableName_companyId_idx" ON "tableName"("companyId");`

## 4. RLS (Row Level Security) Patterns

**IMPORTANT: ALWAYS use the new pattern below. NEVER use the old `has_role`/`has_company_permission` pattern — it is deprecated.**

### Current Pattern (REQUIRED)

Uses standardized policy names (SELECT, INSERT, UPDATE, DELETE) with helper functions:

```sql
ALTER TABLE "tableName" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "SELECT" ON "public"."tableName"
FOR SELECT USING (
  "companyId" = ANY (
    (
      SELECT get_companies_with_employee_permission('module_view')
    )::text[]
  )
);

CREATE POLICY "INSERT" ON "public"."tableName"
FOR INSERT WITH CHECK (
  "companyId" = ANY (
    (
      SELECT get_companies_with_employee_permission('module_create')
    )::text[]
  )
);

CREATE POLICY "UPDATE" ON "public"."tableName"
FOR UPDATE USING (
  "companyId" = ANY (
    (
      SELECT get_companies_with_employee_permission('module_update')
    )::text[]
  )
);

CREATE POLICY "DELETE" ON "public"."tableName"
FOR DELETE USING (
  "companyId" = ANY (
    (
      SELECT get_companies_with_employee_permission('module_delete')
    )::text[]
  )
);
```

### Helper Functions for RLS

- `get_companies_with_employee_permission(permission)` - Returns companies where user has specific permission
- `get_companies_with_employee_role()` - Returns all companies where user is an employee
- `get_companies_with_any_role()` - Returns all companies user has access to
- `get_company_id_from_foreign_key(id, table)` - Gets companyId through foreign key relationship

### Special Cases

#### User-Specific Tables

```sql
CREATE POLICY "SELECT" ON "lessonCompletion"
  FOR SELECT USING (auth.uid()::text = "userId");
```

#### Multi-Permission Policies

```sql
CREATE POLICY "SELECT" ON "public"."account"
FOR SELECT USING (
  "companyId" = ANY (
    SELECT DISTINCT unnest(ARRAY(
      SELECT unnest(get_companies_with_employee_permission('resources_view'))
      UNION
      SELECT unnest(get_companies_with_employee_permission('production_view'))
      UNION
      SELECT unnest(get_companies_with_employee_permission('accounting_view'))
    ))
  )
);
```

## 5. Common Column Types and Constraints

### Standard Columns

- `"id" TEXT NOT NULL DEFAULT id('prefix')` - Primary key
- `"name" TEXT NOT NULL` - Common for most entities
- `"description" TEXT` - Optional descriptions
- `"active" BOOLEAN DEFAULT TRUE` - Soft delete pattern
- `"customFields" JSONB` - Extensibility

### Audit Columns

- `"createdBy" TEXT NOT NULL` - FK to user
- `"createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()`
- `"updatedBy" TEXT` - Nullable FK to user
- `"updatedAt" TIMESTAMP WITH TIME ZONE` - Nullable timestamp

### Financial Columns

- `NUMERIC` or `DECIMAL(10,2)` for monetary values
- `INTEGER` for quantities
- `REAL` for percentages

### Enums

```sql
CREATE TYPE "role" AS ENUM ('customer', 'employee', 'supplier');
CREATE TYPE "planType" AS ENUM ('Trial', 'Per User', 'Flat Fee');
```

## 6. Foreign Key Relationships

### Standard Pattern

```sql
CONSTRAINT "tableName_columnId_fkey" FOREIGN KEY ("columnId")
  REFERENCES "referencedTable"("id") ON DELETE CASCADE ON UPDATE CASCADE
```

### Common Variations

- `ON DELETE CASCADE` - For child records that should be deleted with parent
- `ON DELETE SET NULL` - For optional relationships
- `ON DELETE RESTRICT` - To prevent deletion if references exist

## 7. Indexes and Unique Constraints

### Standard Indexes

```sql
CREATE INDEX "tableName_companyId_idx" ON "tableName"("companyId");
CREATE INDEX "tableName_foreignKeyId_idx" ON "tableName"("foreignKeyId");
```

### Unique Constraints

```sql
CREATE UNIQUE INDEX "index_user_email_key" ON "user"("email");
CREATE UNIQUE INDEX "tableName_companyId_name_key" ON "tableName"("companyId", "name");
```

### Composite Indexes

```sql
CREATE INDEX "lessonCompletion_userId_courseId_lessonId_idx"
  ON "lessonCompletion" ("userId", "courseId", "lessonId");
```

## 8. Views

### Security Invoker Views

```sql
CREATE OR REPLACE VIEW "viewName" WITH(SECURITY_INVOKER=true) AS
  SELECT
    -- columns
  FROM "tableName" t
  INNER JOIN "relatedTable" r ON r.id = t."relatedId"
  -- other joins
```

## 9. Additional Patterns

### Approval Workflow

```sql
"approved" BOOLEAN NOT NULL DEFAULT false,
"approvedBy" TEXT,
CONSTRAINT "tableName_approvedBy_fkey" FOREIGN KEY ("approvedBy") REFERENCES "user"("id")
```

### Soft Delete

- Use `"active" BOOLEAN DEFAULT TRUE` instead of actual deletion
- Some tables use `"blocked" BOOLEAN DEFAULT FALSE`

### Generated Columns

```sql
"fullName" TEXT GENERATED ALWAYS AS ("firstName" || ' ' || "lastName") STORED
```

### Default Values

- Timestamps: `DEFAULT NOW()`
- Booleans: `DEFAULT TRUE` or `DEFAULT FALSE`
- IDs: `DEFAULT id('prefix')`
- Arrays: `DEFAULT ARRAY[]::text[]`
