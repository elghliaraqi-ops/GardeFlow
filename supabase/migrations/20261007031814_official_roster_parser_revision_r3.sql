-- Official Urgences roster parser revision v12.0.1-r3.
-- New clients use revision-aware RPCs. Legacy clients consider r3 current so
-- they do not overwrite a roster already reparsed by a newer client.

create or replace function public.official_roster_import_is_current(
  p_resource_id uuid,
  p_resource_updated_at timestamptz
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;

  return exists(
    select 1
    from public.official_roster_import_runs r
    where r.resource_id = p_resource_id
      and r.resource_updated_at = p_resource_updated_at
      and r.sync_revision in ('v11.6.70-r1', 'v12.0.1-r3')
  );
end;
$function$;

create or replace function public.official_roster_profile_sync_is_current(
  p_resource_id uuid,
  p_resource_updated_at timestamptz,
  p_profile_id uuid
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_profile public.profiles%rowtype;
  v_signature text;
begin
  if auth.uid() is null then raise exception 'Session requise'; end if;
  if p_profile_id <> auth.uid() and not public.is_admin() then
    raise exception 'Accès refusé';
  end if;

  select * into v_profile
  from public.profiles p
  where p.id = p_profile_id
    and p.account_status = 'active';

  if not found then return false; end if;

  v_signature := md5(
    lower(trim(coalesce(v_profile.prenom,''))) || '|' ||
    lower(trim(coalesce(v_profile.nom,''))) || '|' ||
    coalesce(v_profile.phone,'') || '|' ||
    coalesce(v_profile.hospital,'') || '|' ||
    coalesce(v_profile.account_status,'')
  );

  return exists(
    select 1
    from public.official_roster_profile_sync ps
    where ps.resource_id = p_resource_id
      and ps.resource_updated_at = p_resource_updated_at
      and ps.profile_id = p_profile_id
      and ps.profile_signature = v_signature
      and ps.sync_revision in ('v11.6.70-r1', 'v12.0.1-r3')
  );
end;
$function$;

create or replace function public.official_roster_import_is_current_v2(
  p_resource_id uuid,
  p_resource_updated_at timestamptz,
  p_parser_revision text
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;

  if p_parser_revision is null or btrim(p_parser_revision) = '' then
    return false;
  end if;

  return exists(
    select 1
    from public.official_roster_import_runs r
    where r.resource_id = p_resource_id
      and r.resource_updated_at = p_resource_updated_at
      and r.sync_revision = p_parser_revision
  );
end;
$function$;

create or replace function public.official_roster_profile_sync_is_current_v2(
  p_resource_id uuid,
  p_resource_updated_at timestamptz,
  p_profile_id uuid,
  p_parser_revision text
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_profile public.profiles%rowtype;
  v_signature text;
begin
  if auth.uid() is null then raise exception 'Session requise'; end if;
  if p_profile_id <> auth.uid() and not public.is_admin() then
    raise exception 'Accès refusé';
  end if;

  if p_parser_revision is null or btrim(p_parser_revision) = '' then
    return false;
  end if;

  select * into v_profile
  from public.profiles p
  where p.id = p_profile_id
    and p.account_status = 'active';

  if not found then return false; end if;

  v_signature := md5(
    lower(trim(coalesce(v_profile.prenom,''))) || '|' ||
    lower(trim(coalesce(v_profile.nom,''))) || '|' ||
    coalesce(v_profile.phone,'') || '|' ||
    coalesce(v_profile.hospital,'') || '|' ||
    coalesce(v_profile.account_status,'')
  );

  return exists(
    select 1
    from public.official_roster_profile_sync ps
    where ps.resource_id = p_resource_id
      and ps.resource_updated_at = p_resource_updated_at
      and ps.profile_id = p_profile_id
      and ps.profile_signature = v_signature
      and ps.sync_revision = p_parser_revision
  );
end;
$function$;

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
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;

  if p_parser_revision is null or btrim(p_parser_revision) = '' then
    raise exception 'Révision du parseur requise';
  end if;

  v_result := public.import_official_emergency_roster(
    p_resource_id,
    p_resource_updated_at,
    p_assignments,
    p_unmatched_cells
  );

  update public.official_roster_import_runs
  set sync_revision = p_parser_revision,
      imported_at = now(),
      imported_by = auth.uid()
  where resource_id = p_resource_id
    and resource_updated_at = p_resource_updated_at;

  return coalesce(v_result, '{}'::jsonb)
    || jsonb_build_object('parser_revision', p_parser_revision);
end;
$function$;

create or replace function public.import_official_emergency_roster_for_profile_v2(
  p_resource_id uuid,
  p_resource_updated_at timestamptz,
  p_profile_id uuid,
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
begin
  if auth.uid() is null then raise exception 'Session requise'; end if;
  if p_profile_id <> auth.uid() and not public.is_admin() then
    raise exception 'Accès refusé';
  end if;

  if p_parser_revision is null or btrim(p_parser_revision) = '' then
    raise exception 'Révision du parseur requise';
  end if;

  v_result := public.import_official_emergency_roster_for_profile(
    p_resource_id,
    p_resource_updated_at,
    p_profile_id,
    p_assignments,
    p_unmatched_cells
  );

  update public.official_roster_profile_sync
  set sync_revision = p_parser_revision,
      synced_at = now()
  where resource_id = p_resource_id
    and resource_updated_at = p_resource_updated_at
    and profile_id = p_profile_id;

  return coalesce(v_result, '{}'::jsonb)
    || jsonb_build_object('parser_revision', p_parser_revision);
end;
$function$;

revoke all on function public.official_roster_import_is_current_v2(uuid,timestamptz,text) from public;
revoke all on function public.official_roster_import_is_current_v2(uuid,timestamptz,text) from anon;
grant execute on function public.official_roster_import_is_current_v2(uuid,timestamptz,text) to authenticated;

revoke all on function public.official_roster_profile_sync_is_current_v2(uuid,timestamptz,uuid,text) from public;
revoke all on function public.official_roster_profile_sync_is_current_v2(uuid,timestamptz,uuid,text) from anon;
grant execute on function public.official_roster_profile_sync_is_current_v2(uuid,timestamptz,uuid,text) to authenticated;

revoke all on function public.import_official_emergency_roster_v2(uuid,timestamptz,jsonb,text,jsonb) from public;
revoke all on function public.import_official_emergency_roster_v2(uuid,timestamptz,jsonb,text,jsonb) from anon;
grant execute on function public.import_official_emergency_roster_v2(uuid,timestamptz,jsonb,text,jsonb) to authenticated;

revoke all on function public.import_official_emergency_roster_for_profile_v2(uuid,timestamptz,uuid,jsonb,text,jsonb) from public;
revoke all on function public.import_official_emergency_roster_for_profile_v2(uuid,timestamptz,uuid,jsonb,text,jsonb) from anon;
grant execute on function public.import_official_emergency_roster_for_profile_v2(uuid,timestamptz,uuid,jsonb,text,jsonb) to authenticated;
