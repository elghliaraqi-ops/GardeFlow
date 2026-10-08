-- R6 post-deployment compatibility / fail-closed hotfix, 2026-10-08.
-- Historical official PDF resources identify their hospital by slot while
-- shared_resources.hospital is NULL. Never mutate original resource rows.
-- Block recalculations until a verified, nonempty R6 source exists.
-- Urgences ONLY; no service handling.

-- R6 validation hotfix: keep official roster preview dates as DATE.
-- Safe to apply after 20261007231000_garde_functional_lock_r6.sql.

create or replace function public.admin_preview_official_roster_recalculation(
  p_profile_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles%rowtype;
  v_resource public.shared_resources%rowtype;
  v_preview jsonb;
  v_token text;
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;

  select *
  into v_profile
  from public.profiles
  where id = p_profile_id
    and account_status = 'active';

  if not found then
    raise exception 'Médecin actif introuvable';
  end if;

  select *
  into v_resource
  from public.shared_resources
  where kind = 'official_pdf'
    and (
      hospital = v_profile.hospital
      or (
        hospital is null
        and (
          (slot = 'hm6_bouskoura'
            and v_profile.hospital =
              'Hôpital Universitaire International Mohammed VI de Bouskoura')
          or (slot = 'hm6_rabat'
            and v_profile.hospital =
              'Hôpital Universitaire International Mohammed VI de Rabat')
          or (slot = 'hck_casa'
            and v_profile.hospital =
              'Hôpital Universitaire International Cheikh Khalifa de Casablanca')
        )
      )
    )
  order by updated_at desc
  limit 1;

  if not found then
    raise exception 'Aucun planning officiel Urgences pour cet établissement';
  end if;

  -- Fail closed: a legacy official_pdf is NOT an R6-verified source.
  -- Without a verified, populated R6 analysis, an empty target could appear
  -- to authorize removal of all previously synchronized guards.
  if not exists (
    select 1
    from public.official_roster_import_reports r
    where r.resource_id = v_resource.id
      and r.resource_updated_at = v_resource.updated_at
      and r.status in ('green','orange')
      and r.confidence >= 0.90
      and public.guardeflow_roster_revision_rank(r.parser_revision) >= 6
      and r.total_guards > 0
      and exists (
        select 1 from public.official_roster_guards g
        where g.report_id = r.id
          and g.resource_id = v_resource.id
          and g.resource_updated_at = v_resource.updated_at
          and g.duty_area = 'urgences'
      )
  ) then
    raise exception 'Aucune lecture R6 vérifiée des Urgences pour cet établissement. Vérifier puis publier le PDF officiel avant tout recalcul.';
  end if;

  with target as (
    select
      g.id,
      g.date_str as date_str,
      g.shift_id,
      g.confidence,
      g.review_status,
      g.is_disciplinary,
      g.full_name
    from public.official_roster_guards g
    where g.resource_id = v_resource.id
      and g.resource_updated_at = v_resource.updated_at
      and g.matched_profile_id = p_profile_id
      and g.confidence >= 0.90
      and g.review_status in ('green','orange')
  ),
  current_entries as (
    select e.*
    from public.planning_entries e
    where e.owner_id = p_profile_id
      and e.deleted_at is null
  ),
  classified_target as (
    select
      t.*,
      e.id as current_entry_id,
      e.shift_id as current_shift_id,
      e.source_type as current_source_type,
      e.source_resource_id as current_source_resource_id,
      e.source_resource_updated_at as current_source_resource_updated_at,
      coalesce(pm.status,'draft') as month_status,
      public.guardeflow_is_past_month(t.date_str) as past_month
    from target t
    left join current_entries e on e.date_str = t.date_str
    left join public.planning_months pm
      on pm.owner_id = p_profile_id
      and pm.year = extract(year from t.date_str::date)::int
      and pm.month = extract(month from t.date_str::date)::int
  ),
  added as (
    select * from classified_target
    where current_entry_id is null
      and month_status <> 'approved'
      and not past_month
  ),
  unchanged as (
    select * from classified_target
    where current_entry_id is not null
      and current_shift_id = shift_id
      and current_source_type = 'official_emergency'
      and current_source_resource_id = v_resource.id
  ),
  modified as (
    select * from classified_target
    where current_entry_id is not null
      and current_shift_id <> shift_id
      and current_source_type = 'official_emergency'
      and current_source_resource_id = v_resource.id
      and month_status <> 'approved'
      and not past_month
  ),
  conflicts as (
    select * from classified_target
    where
      (current_entry_id is not null and
       coalesce(current_source_type,'') <> 'official_emergency')
      or month_status = 'approved'
      or past_month
  ),
  removed as (
    select e.*
    from current_entries e
    where e.source_type = 'official_emergency'
      and e.source_resource_id = v_resource.id
      and not exists (
        select 1 from target t where t.date_str = e.date_str
      )
      and not public.guardeflow_is_past_month(e.date_str)
      and coalesce((
        select pm.status
        from public.planning_months pm
        where pm.owner_id = p_profile_id
          and pm.year = extract(year from e.date_str)::int
          and pm.month = extract(month from e.date_str)::int
      ),'draft') <> 'approved'
  )
  select jsonb_build_object(
    'profile_id', p_profile_id,
    'profile_name', trim(v_profile.prenom || ' ' || v_profile.nom),
    'hospital', v_profile.hospital,
    'resource_id', v_resource.id,
    'resource_updated_at', v_resource.updated_at,
    'official_guard_count', (select count(*) from target),
    'added', coalesce((select jsonb_agg(to_jsonb(a) order by a.date_str) from added a),'[]'::jsonb),
    'modified', coalesce((select jsonb_agg(to_jsonb(m) order by m.date_str) from modified m),'[]'::jsonb),
    'removed', coalesce((select jsonb_agg(to_jsonb(r) order by r.date_str) from removed r),'[]'::jsonb),
    'unchanged', coalesce((select jsonb_agg(to_jsonb(u) order by u.date_str) from unchanged u),'[]'::jsonb),
    'conflicts', coalesce((select jsonb_agg(to_jsonb(c) order by c.date_str) from conflicts c),'[]'::jsonb)
  )
  into v_preview;

  v_token := md5(v_preview::text);

  return v_preview || jsonb_build_object('preview_token', v_token);
end;
$$;
