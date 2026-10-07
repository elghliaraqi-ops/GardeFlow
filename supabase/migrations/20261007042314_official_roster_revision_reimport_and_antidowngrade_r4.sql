create or replace function public.guardeflow_roster_revision_rank(p_revision text)
returns integer
language sql
immutable
as $function$
  select coalesce(
    nullif((regexp_match(coalesce(p_revision,''), 'r([0-9]+)$'))[1], '')::int,
    0
  );
$function$;

revoke all on function public.guardeflow_roster_revision_rank(text) from public;
revoke all on function public.guardeflow_roster_revision_rank(text) from anon;
grant execute on function public.guardeflow_roster_revision_rank(text) to authenticated;

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
      and public.guardeflow_roster_revision_rank(r.sync_revision)
          >= public.guardeflow_roster_revision_rank(p_parser_revision)
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
      and public.guardeflow_roster_revision_rank(ps.sync_revision)
          >= public.guardeflow_roster_revision_rank(p_parser_revision)
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
  v_safe_unmatched jsonb;
  v_current_revision text;
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;

  if public.guardeflow_roster_revision_rank(p_parser_revision) < 4 then
    raise exception 'Parseur officiel obsolète : mise à jour de GardeFlow requise';
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

  -- Le legacy considère n'importe quelle ligne d'import comme "déjà traitée".
  -- On retire uniquement le marqueur de l'ancienne révision dans la même
  -- transaction afin de forcer un vrai retraitement ; en cas d'erreur tout
  -- est rollbacké.
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
  v_safe_unmatched jsonb;
  v_current_revision text;
begin
  if auth.uid() is null then raise exception 'Session requise'; end if;
  if p_profile_id <> auth.uid() and not public.is_admin() then
    raise exception 'Accès refusé';
  end if;

  if public.guardeflow_roster_revision_rank(p_parser_revision) < 4 then
    raise exception 'Parseur officiel obsolète : mise à jour de GardeFlow requise';
  end if;

  select ps.sync_revision
  into v_current_revision
  from public.official_roster_profile_sync ps
  where ps.resource_id = p_resource_id
    and ps.resource_updated_at = p_resource_updated_at
    and ps.profile_id = p_profile_id
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
    p_profile_id,
    p_assignments,
    p_unmatched_cells
  );

  v_result := public.import_official_emergency_roster_for_profile(
    p_resource_id,
    p_resource_updated_at,
    p_profile_id,
    p_assignments,
    v_safe_unmatched
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

-- Les anciennes RPC d'import restent utilisables uniquement depuis les
-- fonctions SECURITY DEFINER du serveur. Les anciens clients ne peuvent plus
-- contourner la protection de révision.
revoke execute on function public.import_official_emergency_roster(uuid,timestamptz,jsonb,jsonb) from authenticated;
revoke execute on function public.import_official_emergency_roster_for_profile(uuid,timestamptz,uuid,jsonb,jsonb) from authenticated;

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
      and public.guardeflow_roster_revision_rank(r.sync_revision) >= 4
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
      and public.guardeflow_roster_revision_rank(ps.sync_revision) >= 4
  );
end;
$function$;
