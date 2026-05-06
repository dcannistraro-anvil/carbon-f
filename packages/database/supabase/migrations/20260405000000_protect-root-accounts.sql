-- Protect root accounts (Balance Sheet, Income Statement) from edits/deletes.
--
-- Adds a boolean "isSystem" column to account. Root accounts are marked
-- isSystem = true and a trigger prevents UPDATE or DELETE on those rows.

-- 1. Add column
ALTER TABLE "account" ADD COLUMN IF NOT EXISTS "isSystem" BOOLEAN NOT NULL DEFAULT false;

-- 2. Backfill: root accounts have no parent
UPDATE "account" SET "isSystem" = true WHERE "parentId" IS NULL;

-- 3. Recreate the accounts view so it picks up the new column
DROP VIEW IF EXISTS "accounts";
CREATE OR REPLACE VIEW "accounts" WITH(SECURITY_INVOKER=true) AS SELECT "account".* FROM "account";

-- 4. Trigger function
CREATE OR REPLACE FUNCTION "protect_system_accounts"()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD."isSystem" = true THEN
      RAISE EXCEPTION 'System accounts cannot be deleted';
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF OLD."isSystem" = true THEN
      -- Allow toggling active flag only (for soft-disable if ever needed)
      IF NEW."name"             IS DISTINCT FROM OLD."name"
        OR NEW."number"         IS DISTINCT FROM OLD."number"
        OR NEW."parentId"       IS DISTINCT FROM OLD."parentId"
        OR NEW."isGroup"        IS DISTINCT FROM OLD."isGroup"
        OR NEW."accountType"    IS DISTINCT FROM OLD."accountType"
        OR NEW."incomeBalance"  IS DISTINCT FROM OLD."incomeBalance"
        OR NEW."class"          IS DISTINCT FROM OLD."class"
        OR NEW."isSystem"       IS DISTINCT FROM OLD."isSystem"
      THEN
        RAISE EXCEPTION 'System accounts cannot be modified';
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;

-- 5. Attach trigger
CREATE TRIGGER "account_protect_system"
  BEFORE UPDATE OR DELETE ON "account"
  FOR EACH ROW
  EXECUTE FUNCTION "protect_system_accounts"();
