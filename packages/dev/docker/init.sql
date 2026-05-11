-- Set every supabase service role's password to "postgres" so:
--   * cli.ts bootstrap connects as supabase_admin via host TCP
--   * gotrue/storage/postgrest/realtime authenticate without per-role secrets
-- Runs as the image's bundled superuser during first postgres init
-- (mounted to /docker-entrypoint-initdb.d/init-scripts/).

ALTER USER supabase_admin            WITH PASSWORD 'postgres';
ALTER USER supabase_auth_admin       WITH PASSWORD 'postgres';
ALTER USER supabase_storage_admin    WITH PASSWORD 'postgres';
ALTER USER authenticator             WITH PASSWORD 'postgres';

GRANT anon, authenticated, service_role TO authenticator;

CREATE SCHEMA IF NOT EXISTS _realtime AUTHORIZATION supabase_admin;
