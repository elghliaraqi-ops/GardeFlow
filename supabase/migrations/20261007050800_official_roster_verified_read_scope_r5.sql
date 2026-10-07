drop policy if exists official_roster_verified_reads_deny_direct
on public.official_roster_verified_reads;

create policy official_roster_verified_reads_deny_direct
on public.official_roster_verified_reads
as restrictive
for all
to authenticated
using (false)
with check (false);

create or replace function public.get_official_roster_verified_read(
  p_resource_id uuid,
  p_resource_updated_at timestamptz,
  p_parser_revision text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_payload jsonb;
begin
  if auth.uid() is null or not public.current_account_active() then
    raise exception 'Session active requise';
  end if;

  select r.extraction
  into v_payload
  from public.official_roster_verified_reads r
  join public.shared_resources sr on sr.id = r.resource_id
  where r.resource_id = p_resource_id
    and r.resource_updated_at = p_resource_updated_at
    and r.parser_revision = p_parser_revision
    and coalesce((r.extraction->>'verified')::boolean, false) = true
    and (
      public.is_admin()
      or sr.hospital = public.current_hospital()
    );

  return v_payload;
end;
$function$;

revoke all on function public.get_official_roster_verified_read(
  uuid,timestamptz,text
) from public, anon;
grant execute on function public.get_official_roster_verified_read(
  uuid,timestamptz,text
) to authenticated;
