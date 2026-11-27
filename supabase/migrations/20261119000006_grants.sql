-- =====================================================================
-- 0006 explicit grants
-- Supabase projects can be created with "Grant API access to new tables automatically" switched
-- off, so nothing here may depend on default privileges. Grants are explicit and deliberately
-- narrow; Row Level Security (migrations 0001-0005) decides which rows each role can touch.
--   anon           : no table access at all (signed-out visitors use public_settings() only)
--   authenticated  : table access, limited row by row by RLS policies
--   service_role   : full access, used only by Edge Functions
-- =====================================================================

grant usage on schema public to anon, authenticated, service_role;

grant select, insert, update, delete on all tables in schema public to authenticated;
grant all on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to authenticated, service_role;

-- Tables and sequences added by later migrations get the same grants automatically.
alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant usage, select on sequences to authenticated, service_role;

-- Storage objects: students upload and read screenshots through RLS policies on storage.objects.
grant usage on schema storage to authenticated, service_role;
