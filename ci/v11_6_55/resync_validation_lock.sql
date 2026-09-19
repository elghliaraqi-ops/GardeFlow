-- GardeFlow V11.6.55
-- La superposition manuelle du PDF n'est autorisée que tant que le mois
-- principal du planning n'est pas définitivement validé.

create or replace function public.official_roster_resource_main_month(
  p_resource_id uuid,
  p_resource_updated_at timestamptz
)
returns table(year integer, month integer)
language sql
stable
security definer
set search_path = public
as $$
  with all_dates as (
    select e.date_str as d
    from public.planning_entries e
    where e.source_resource_id = p_resource_id
      and e.source_resource_updated_at = p_resource_updated_at
      and e.deleted_at is null

    union all

    select nullif(cell->>'date','')::date as d
    from public.official_roster_import_runs ir
    cross join lateral jsonb_array_elements(
      coalesce(ir.unmatched_cells, '[]'::jsonb)
    ) cell
    where ir.resource_id = p_resource_id
      and ir.resource_updated_at = p_resource_updated_at
      and nullif(cell->>'date','') is not null
  ),
  counts as (
    select
      extract(year from d)::int as y,
      extract(month from d)::int as m,
      count(distinct d) as date_count
    from all_dates
    where d is not null
    group by 1,2
  )
  select y,m
  from counts
  order by date_count desc, y desc, m desc
  limit 1;
$$;

revoke all on function public.official_roster_resource_main_month(uuid,timestamptz)
  from public, anon, authenticated;


create or replace function public.reset_my_official_roster_profile_sync(
  p_resource_id uuid,
  p_resource_updated_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  r public.shared_resources%rowtype;
  p public.profiles%rowtype;
  expected_hospital text;
  main_year integer;
  main_month integer;
begin
  if uid is null then raise exception 'Session requise'; end if;

  select * into r
  from public.shared_resources
  where id=p_resource_id and kind='official_pdf';

  if not found then raise exception 'Planning officiel introuvable'; end if;
  if r.updated_at is distinct from p_resource_updated_at then
    raise exception 'Le PDF a été remplacé. Actualisez la page.';
  end if;

  select * into p
  from public.profiles
  where id=uid and account_status='active';

  if not found then raise exception 'Profil actif introuvable'; end if;

  expected_hospital := case r.slot
    when 'hm6_bouskoura' then 'Hôpital Universitaire International Mohammed VI de Bouskoura'
    when 'hm6_rabat' then 'Hôpital Universitaire International Mohammed VI de Rabat'
    when 'hck_casa' then 'Hôpital Universitaire International Cheikh Khalifa de Casablanca'
    else null
  end;

  if expected_hospital is null or p.hospital is distinct from expected_hospital then
    raise exception 'Ce planning officiel ne correspond pas à votre établissement';
  end if;

  select m.year,m.month
    into main_year,main_month
  from public.official_roster_resource_main_month(
    p_resource_id,
    p_resource_updated_at
  ) m;

  if main_year is null or main_month is null then
    raise exception 'Impossible d’identifier le mois principal de ce planning officiel';
  end if;

  if exists(
    select 1
    from public.planning_months pm
    where pm.owner_id=uid
      and pm.year=main_year
      and pm.month=main_month
      and pm.status='approved'
  ) then
    raise exception 'Calendrier validé définitivement : la superposition ne peut plus être refaite.';
  end if;

  delete from public.official_roster_profile_sync
  where resource_id=p_resource_id
    and resource_updated_at=p_resource_updated_at
    and profile_id=uid;
end;
$$;

grant execute on function public.reset_my_official_roster_profile_sync(uuid,timestamptz)
  to authenticated;


create or replace function public.official_roster_my_summary(
  p_resource_id uuid,
  p_resource_updated_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  total_count int := 0;
  disciplinary_count int := 0;
  main_year integer;
  main_month integer;
  can_resync boolean := false;
begin
  if uid is null then raise exception 'Session requise'; end if;

  select
    count(*)::int,
    count(*) filter (
      where e.is_disciplinary
         or public.is_current_disciplinary_guard(e.owner_id,e.date_str)
    )::int
  into total_count, disciplinary_count
  from public.planning_entries e
  where e.owner_id=uid
    and e.deleted_at is null
    and e.source_resource_id=p_resource_id
    and e.source_resource_updated_at=p_resource_updated_at;

  select m.year,m.month
    into main_year,main_month
  from public.official_roster_resource_main_month(
    p_resource_id,
    p_resource_updated_at
  ) m;

  if main_year is not null and main_month is not null then
    can_resync := not exists(
      select 1
      from public.planning_months pm
      where pm.owner_id=uid
        and pm.year=main_year
        and pm.month=main_month
        and pm.status='approved'
    );
  end if;

  return jsonb_build_object(
    'total',coalesce(total_count,0),
    'disciplinary',coalesce(disciplinary_count,0),
    'year',main_year,
    'month',main_month,
    'can_resync',can_resync
  );
end;
$$;

grant execute on function public.official_roster_my_summary(uuid,timestamptz)
  to authenticated;
