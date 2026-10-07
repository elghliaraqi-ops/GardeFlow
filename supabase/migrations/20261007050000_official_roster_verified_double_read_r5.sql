create table if not exists public.official_roster_verified_reads (
  resource_id uuid not null references public.shared_resources(id) on delete cascade,
  resource_updated_at timestamptz not null,
  parser_revision text not null,
  engine text not null default 'openai_pdf_double_read',
  extraction jsonb not null,
  confidence numeric not null default 0,
  warnings jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  primary key (resource_id, resource_updated_at, parser_revision)
);

alter table public.official_roster_verified_reads enable row level security;

revoke all on public.official_roster_verified_reads from public, anon, authenticated;

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
  where r.resource_id = p_resource_id
    and r.resource_updated_at = p_resource_updated_at
    and r.parser_revision = p_parser_revision
    and coalesce((r.extraction->>'verified')::boolean, false) = true;

  return v_payload;
end;
$function$;

revoke all on function public.get_official_roster_verified_read(uuid,timestamptz,text)
from public, anon;
grant execute on function public.get_official_roster_verified_read(uuid,timestamptz,text)
to authenticated;

create or replace function public.import_official_emergency_roster_v2(
  p_resource_id uuid,
  p_resource_updated_at timestamptz,
  p_assignments jsonb,
  p_parser_revision text,
  p_unmatched_cells jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_result jsonb;
  v_safe_unmatched jsonb;
  v_current_revision text;
  v_hospital text;
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;

  if public.guardeflow_roster_revision_rank(p_parser_revision) < 5 then
    raise exception 'Parseur officiel obsolète : mise à jour de GardeFlow requise';
  end if;

  select sr.hospital
  into v_hospital
  from public.shared_resources sr
  where sr.id = p_resource_id
    and sr.kind = 'official_pdf'
    and sr.updated_at = p_resource_updated_at;

  if v_hospital is null then
    raise exception 'Planning officiel introuvable ou remplacé';
  end if;

  select r.sync_revision
  into v_current_revision
  from public.official_roster_import_runs r
  where r.resource_id = p_resource_id
    and r.resource_updated_at = p_resource_updated_at
  for update;

  if found and public.guardeflow_roster_revision_rank(v_current_revision)
      > public.guardeflow_roster_revision_rank(p_parser_revision) then
    raise exception 'Révision du planning plus récente déjà appliquée';
  end if;

  if found and public.guardeflow_roster_revision_rank(v_current_revision)
      = public.guardeflow_roster_revision_rank(p_parser_revision) then
    return jsonb_build_object(
      'already_processed', true,
      'inserted', 0,
      'updated', 0,
      'removed', 0,
      'parser_revision', v_current_revision
    );
  end if;

  v_safe_unmatched := public.guardeflow_preserve_uncovered_official_dates(
    p_resource_id,
    null,
    p_assignments,
    p_unmatched_cells
  );

  delete from public.official_roster_import_runs r
  where r.resource_id = p_resource_id
    and r.resource_updated_at = p_resource_updated_at;

  v_result := public.import_official_emergency_roster(
    p_resource_id,
    p_resource_updated_at,
    p_assignments,
    v_safe_unmatched
  );

  update public.official_roster_import_runs
  set sync_revision = p_parser_revision,
      imported_at = now(),
      imported_by = auth.uid()
  where resource_id = p_resource_id
    and resource_updated_at = p_resource_updated_at;

  -- A successful full-roster import is authoritative for every currently
  -- active profile in the hospital, including profiles with zero guards.
  -- This prevents each phone from reparsing the same PDF independently.
  insert into public.official_roster_profile_sync(
    resource_id,
    resource_updated_at,
    profile_id,
    profile_signature,
    sync_revision,
    synced_at,
    assignment_count,
    inserted_count,
    updated_count,
    removed_count,
    skipped_manual_count,
    skipped_locked_count,
    invalid_count,
    unmatched_cells
  )
  select
    p_resource_id,
    p_resource_updated_at,
    p.id,
    md5(
      lower(trim(coalesce(p.prenom,''))) || '|' ||
      lower(trim(coalesce(p.nom,''))) || '|' ||
      coalesce(p.phone,'') || '|' ||
      coalesce(p.hospital,'') || '|' ||
      coalesce(p.account_status,'')
    ),
    p_parser_revision,
    now(),
    (
      select count(*)::int
      from jsonb_array_elements(coalesce(p_assignments,'[]'::jsonb)) a
      where a->>'profile_id' = p.id::text
    ),
    0,0,0,0,0,0,
    coalesce(p_unmatched_cells,'[]'::jsonb)
  from public.profiles p
  where p.account_status = 'active'
    and p.hospital = v_hospital
  on conflict (resource_id, resource_updated_at, profile_id) do update
  set profile_signature = excluded.profile_signature,
      sync_revision = excluded.sync_revision,
      synced_at = excluded.synced_at,
      assignment_count = excluded.assignment_count,
      unmatched_cells = excluded.unmatched_cells;

  return coalesce(v_result, '{}'::jsonb)
    || jsonb_build_object('parser_revision', p_parser_revision);
end;
$function$;

revoke all on function public.import_official_emergency_roster_v2(
  uuid,timestamptz,jsonb,text,jsonb
) from public, anon;
grant execute on function public.import_official_emergency_roster_v2(
  uuid,timestamptz,jsonb,text,jsonb
) to authenticated;
