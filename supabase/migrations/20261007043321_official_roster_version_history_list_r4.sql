-- Seed the currently published PDFs as the first immutable history entries.
insert into public.official_roster_versions(
  resource_id,
  resource_updated_at,
  slot,
  hospital,
  storage_path,
  display_name,
  uploaded_by,
  created_at,
  parser_revision,
  status
)
select
  r.id,
  r.updated_at,
  r.slot,
  coalesce(r.hospital, public.guardeflow_expected_hospital_for_slot(r.slot)),
  r.storage_path,
  r.display_name,
  r.uploaded_by,
  r.updated_at,
  null,
  'validated'
from public.shared_resources r
where r.kind='official_pdf'
  and r.slot is not null
on conflict(resource_id,resource_updated_at) do nothing;

create or replace function public.list_official_roster_versions(p_slot text)
returns table(
  id uuid,
  kind text,
  slot text,
  storage_path text,
  display_name text,
  mime_type text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if auth.uid() is null or not public.current_account_active() then
    raise exception 'Compte actif requis';
  end if;

  return query
  select
    v.resource_id as id,
    'official_pdf'::text as kind,
    v.slot,
    v.storage_path,
    v.display_name,
    'application/pdf'::text as mime_type,
    v.created_at,
    v.resource_updated_at as updated_at
  from public.official_roster_versions v
  where v.slot=p_slot
    and v.status='validated'
  order by v.resource_updated_at desc;
end;
$function$;

revoke all on function public.list_official_roster_versions(text) from public, anon;
grant execute on function public.list_official_roster_versions(text) to authenticated;
