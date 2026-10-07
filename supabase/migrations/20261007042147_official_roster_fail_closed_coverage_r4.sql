create or replace function public.guardeflow_preserve_uncovered_official_dates(
  p_resource_id uuid,
  p_profile_id uuid,
  p_assignments jsonb,
  p_unmatched_cells jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_min_date date;
  v_max_date date;
  v_result jsonb := coalesce(p_unmatched_cells, '[]'::jsonb);
begin
  with candidate_dates as (
    select case
      when value ? 'date'
       and (value->>'date') ~ '^\d{4}-\d{2}-\d{2}$'
      then (value->>'date')::date
      else null
    end as d
    from jsonb_array_elements(coalesce(p_assignments,'[]'::jsonb))
    union all
    select case
      when value ? 'date'
       and (value->>'date') ~ '^\d{4}-\d{2}-\d{2}$'
      then (value->>'date')::date
      else null
    end as d
    from jsonb_array_elements(coalesce(p_unmatched_cells,'[]'::jsonb))
  )
  select min(d), max(d)
  into v_min_date, v_max_date
  from candidate_dates
  where d is not null;

  if v_min_date is null or v_max_date is null then
    return v_result;
  end if;

  select v_result || coalesce(
    jsonb_agg(
      jsonb_build_object(
        'date', e.date_str::text,
        'reason', 'outside_current_pdf_coverage'
      )
      order by e.date_str
    ),
    '[]'::jsonb
  )
  into v_result
  from (
    select distinct e.date_str
    from public.planning_entries e
    where e.source_type='official_emergency'
      and e.source_resource_id=p_resource_id
      and e.deleted_at is null
      and (p_profile_id is null or e.owner_id=p_profile_id)
      and (e.date_str < v_min_date or e.date_str > v_max_date)
  ) e;

  return coalesce(v_result,'[]'::jsonb);
end;
$function$;

revoke all on function public.guardeflow_preserve_uncovered_official_dates(uuid,uuid,jsonb,jsonb) from public;
revoke all on function public.guardeflow_preserve_uncovered_official_dates(uuid,uuid,jsonb,jsonb) from anon;
revoke all on function public.guardeflow_preserve_uncovered_official_dates(uuid,uuid,jsonb,jsonb) from authenticated;

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
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;

  if p_parser_revision is null or btrim(p_parser_revision) = '' then
    raise exception 'Révision du parseur requise';
  end if;

  v_safe_unmatched := public.guardeflow_preserve_uncovered_official_dates(
    p_resource_id,
    null,
    p_assignments,
    p_unmatched_cells
  );

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
begin
  if auth.uid() is null then raise exception 'Session requise'; end if;
  if p_profile_id <> auth.uid() and not public.is_admin() then
    raise exception 'Accès refusé';
  end if;

  if p_parser_revision is null or btrim(p_parser_revision) = '' then
    raise exception 'Révision du parseur requise';
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
