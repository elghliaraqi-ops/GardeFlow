-- GardeFlow V11.6.40
-- Fixes PostgREST error 21000 ("DELETE requires a WHERE clause") when an
-- administrator clears the audit history from the app.

create or replace function public.admin_clear_audit_log()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count bigint;
begin
  if not public.is_admin() then
    raise exception 'Action réservée à un administrateur';
  end if;

  delete from public.audit_log
  where id is not null;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
