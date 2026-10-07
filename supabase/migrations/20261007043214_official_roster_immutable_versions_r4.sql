create table if not exists public.official_roster_versions (
  id uuid primary key default gen_random_uuid(),
  resource_id uuid not null references public.shared_resources(id) on delete cascade,
  resource_updated_at timestamptz not null,
  slot text not null,
  hospital text not null,
  storage_path text not null unique,
  display_name text not null,
  uploaded_by uuid,
  created_at timestamptz not null default now(),
  first_date date,
  last_date date,
  coverage_dates jsonb not null default '[]'::jsonb,
  parser_revision text,
  status text not null default 'validated'
    check (status in ('validated','invalid')),
  validation_errors jsonb not null default '[]'::jsonb,
  unique(resource_id, resource_updated_at)
);

create index if not exists official_roster_versions_slot_updated_idx
  on public.official_roster_versions(slot, resource_updated_at desc);

alter table public.official_roster_versions enable row level security;

drop policy if exists official_roster_versions_read on public.official_roster_versions;
create policy official_roster_versions_read
on public.official_roster_versions
for select
to authenticated
using (public.current_account_active());

revoke insert, update, delete on public.official_roster_versions from authenticated;
grant select on public.official_roster_versions to authenticated;

create or replace function public.publish_official_roster_version(
  p_slot text,
  p_storage_path text,
  p_display_name text,
  p_resource_updated_at timestamptz,
  p_first_date date,
  p_last_date date,
  p_coverage_dates jsonb,
  p_parser_revision text
)
returns public.shared_resources
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_hospital text;
  v_existing public.shared_resources%rowtype;
  v_resource public.shared_resources%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;

  if p_slot not in ('hm6_bouskoura','hm6_rabat','hck_casa') then
    raise exception 'Slot de planning officiel invalide';
  end if;

  if p_storage_path is null
     or p_storage_path not like 'official_versions/%' then
    raise exception 'Chemin de version officielle invalide';
  end if;

  if p_parser_revision is null
     or public.guardeflow_roster_revision_rank(p_parser_revision) < 4 then
    raise exception 'Parseur officiel obsolète';
  end if;

  if p_first_date is null or p_last_date is null or p_last_date < p_first_date then
    raise exception 'Couverture de dates invalide';
  end if;

  if jsonb_typeof(coalesce(p_coverage_dates,'[]'::jsonb)) <> 'array' then
    raise exception 'Couverture de dates invalide';
  end if;

  v_hospital := public.guardeflow_expected_hospital_for_slot(p_slot);
  if v_hospital is null then
    raise exception 'Établissement invalide';
  end if;

  select *
  into v_existing
  from public.shared_resources
  where kind='official_pdf'
    and slot=p_slot
  for update;

  -- Archive la version qui était courante avant de déplacer le pointeur.
  if found then
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
    values(
      v_existing.id,
      v_existing.updated_at,
      p_slot,
      v_hospital,
      v_existing.storage_path,
      v_existing.display_name,
      v_existing.uploaded_by,
      v_existing.updated_at,
      null,
      'validated'
    )
    on conflict (resource_id, resource_updated_at) do nothing;
  end if;

  insert into public.shared_resources(
    kind,slot,storage_path,display_name,mime_type,uploaded_by,updated_at,hospital
  )
  values(
    'official_pdf',
    p_slot,
    p_storage_path,
    p_display_name,
    'application/pdf',
    auth.uid(),
    p_resource_updated_at,
    v_hospital
  )
  on conflict(kind,slot) do update
  set storage_path=excluded.storage_path,
      display_name=excluded.display_name,
      mime_type=excluded.mime_type,
      uploaded_by=excluded.uploaded_by,
      updated_at=excluded.updated_at,
      hospital=excluded.hospital
  returning * into v_resource;

  insert into public.official_roster_versions(
    resource_id,
    resource_updated_at,
    slot,
    hospital,
    storage_path,
    display_name,
    uploaded_by,
    created_at,
    first_date,
    last_date,
    coverage_dates,
    parser_revision,
    status,
    validation_errors
  )
  values(
    v_resource.id,
    p_resource_updated_at,
    p_slot,
    v_hospital,
    p_storage_path,
    p_display_name,
    auth.uid(),
    now(),
    p_first_date,
    p_last_date,
    coalesce(p_coverage_dates,'[]'::jsonb),
    p_parser_revision,
    'validated',
    '[]'::jsonb
  )
  on conflict(resource_id,resource_updated_at) do update
  set storage_path=excluded.storage_path,
      display_name=excluded.display_name,
      uploaded_by=excluded.uploaded_by,
      first_date=excluded.first_date,
      last_date=excluded.last_date,
      coverage_dates=excluded.coverage_dates,
      parser_revision=excluded.parser_revision,
      status='validated',
      validation_errors='[]'::jsonb;

  return v_resource;
end;
$function$;

revoke all on function public.publish_official_roster_version(
  text,text,text,timestamptz,date,date,jsonb,text
) from public, anon;
grant execute on function public.publish_official_roster_version(
  text,text,text,timestamptz,date,date,jsonb,text
) to authenticated;

-- Old clients must no longer be able to replace the canonical official PDF
-- with an overwrite-style path.
create or replace function public.guardeflow_enforce_versioned_official_pdf()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  if new.kind='official_pdf'
     and new.storage_path not like 'official_versions/%' then
    if tg_op='INSERT'
       or old.storage_path is distinct from new.storage_path
       or old.updated_at is distinct from new.updated_at then
      raise exception 'Publication officielle obsolète : mettez GardeFlow à jour';
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_guardeflow_versioned_official_pdf
on public.shared_resources;

create trigger trg_guardeflow_versioned_official_pdf
before insert or update on public.shared_resources
for each row
execute function public.guardeflow_enforce_versioned_official_pdf();

revoke all on function public.guardeflow_enforce_versioned_official_pdf() from public, anon, authenticated;
