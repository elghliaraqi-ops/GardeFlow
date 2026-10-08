-- Explicitly remove Supabase anon-role EXECUTE privileges from R6 admin RPCs.
-- The functions also fail closed via public.is_admin(), but the API surface
-- itself should not be exposed to anonymous callers.

revoke execute on function public.save_official_roster_analysis_r6(
  uuid,timestamptz,jsonb,jsonb,jsonb
) from anon;
revoke execute on function public.admin_set_official_roster_identity_link(
  text,text,text,text,uuid,text
) from anon;
revoke execute on function public.admin_delete_official_roster_identity_link(
  uuid,text
) from anon;
revoke execute on function public.admin_correct_official_roster_guard(
  uuid,jsonb,text
) from anon;
revoke execute on function public.admin_preview_official_roster_recalculation(
  uuid
) from anon;
revoke execute on function public.admin_apply_official_roster_recalculation(
  uuid,text
) from anon;
revoke execute on function public.admin_log_official_roster_global_recalculation(
  jsonb,jsonb
) from anon;
