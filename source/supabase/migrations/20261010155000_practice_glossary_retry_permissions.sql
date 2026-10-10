-- Allow the authenticated Edge Function (service_role only) to release
-- previous-day failed attempts before a single new budgeted INSERT.
-- All other client roles remain denied; RLS remains enabled.
grant delete on table public.practice_context_glossary_cache to service_role;
revoke delete on table public.practice_context_glossary_cache from anon, authenticated;
