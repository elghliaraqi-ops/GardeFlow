-- GardeFlow V11.6.68 - official roster individual-import integrity
-- Individual clients may parse the PDF, but the server remains authoritative.

create extension if not exists unaccent with schema extensions;

create or replace function public.normalize_official_roster_text(p_text text)
returns text
language sql
stable
set search_path = public, extensions
as $$
  select trim(
    regexp_replace(
      lower(extensions.unaccent(coalesce(p_text,''))),
      '[^a-z0-9]+',
      ' ',
      'g'
    )
  );
$$;

revoke all on function public.normalize_official_roster_text(text)
  from public, anon, authenticated;


create or replace function public.official_unmatched_assignment_matches_profile(
  p_resource_id uuid,
  p_resource_updated_at timestamptz,
  p_profile_id uuid,
  p_date date,
  p_shift_id text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
declare
  v_profile public.profiles%rowtype;
  v_first_last text;
  v_last_first text;
begin
  select * into v_profile
  from public.profiles
  where id=p_profile_id and account_status='active';

  if not found then return false; end if;

  v_first_last := public.normalize_official_roster_text(
    coalesce(v_profile.prenom,'') || ' ' || coalesce(v_profile.nom,'')
  );
  v_last_first := public.normalize_official_roster_text(
    coalesce(v_profile.nom,'') || ' ' || coalesce(v_profile.prenom,'')
  );

  if v_first_last='' or v_last_first='' then return false; end if;

  if p_shift_id='urg-24h' then
    return (
      exists(
        select 1
        from public.official_roster_import_runs ir
        cross join lateral jsonb_array_elements(coalesce(ir.unmatched_cells,'[]'::jsonb)) cell
        where ir.resource_id=p_resource_id
          and ir.resource_updated_at=p_resource_updated_at
          and nullif(cell->>'date','')::date=p_date
          and cell->>'shift_id'='urg-24h'
          and (
            ' ' || public.normalize_official_roster_text(cell->>'text') || ' '
              like '% ' || v_first_last || ' %'
            or
            ' ' || public.normalize_official_roster_text(cell->>'text') || ' '
              like '% ' || v_last_first || ' %'
          )
      )
      or (
        exists(
          select 1
          from public.official_roster_import_runs ir
          cross join lateral jsonb_array_elements(coalesce(ir.unmatched_cells,'[]'::jsonb)) cell
          where ir.resource_id=p_resource_id
            and ir.resource_updated_at=p_resource_updated_at
            and nullif(cell->>'date','')::date=p_date
            and cell->>'shift_id'='urg-jour'
            and (
              ' ' || public.normalize_official_roster_text(cell->>'text') || ' '
                like '% ' || v_first_last || ' %'
              or
              ' ' || public.normalize_official_roster_text(cell->>'text') || ' '
                like '% ' || v_last_first || ' %'
            )
        )
        and exists(
          select 1
          from public.official_roster_import_runs ir
          cross join lateral jsonb_array_elements(coalesce(ir.unmatched_cells,'[]'::jsonb)) cell
          where ir.resource_id=p_resource_id
            and ir.resource_updated_at=p_resource_updated_at
            and nullif(cell->>'date','')::date=p_date
            and cell->>'shift_id'='urg-nuit'
            and (
              ' ' || public.normalize_official_roster_text(cell->>'text') || ' '
                like '% ' || v_first_last || ' %'
              or
              ' ' || public.normalize_official_roster_text(cell->>'text') || ' '
                like '% ' || v_last_first || ' %'
            )
        )
      )
    );
  end if;

  return exists(
    select 1
    from public.official_roster_import_runs ir
    cross join lateral jsonb_array_elements(coalesce(ir.unmatched_cells,'[]'::jsonb)) cell
    where ir.resource_id=p_resource_id
      and ir.resource_updated_at=p_resource_updated_at
      and nullif(cell->>'date','')::date=p_date
      and cell->>'shift_id'=p_shift_id
      and (
        ' ' || public.normalize_official_roster_text(cell->>'text') || ' '
          like '% ' || v_first_last || ' %'
        or
        ' ' || public.normalize_official_roster_text(cell->>'text') || ' '
          like '% ' || v_last_first || ' %'
      )
  );
end;
$$;

revoke all on function public.official_unmatched_assignment_matches_profile(
  uuid,timestamptz,uuid,date,text
) from public, anon, authenticated;


create or replace function public.protect_official_import_integrity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_official_import boolean :=
    coalesce(current_setting('gardeflow.official_import',true),'0')='1';
  v_allowed boolean := false;
begin
  if not v_official_import then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;

  -- Full official import and trusted server maintenance retain their privileges.
  if public.is_admin() or auth.role()='service_role' then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;

  if auth.uid() is null then
    raise exception 'Session requise';
  end if;

  if tg_op='DELETE' then
    raise exception 'Une garde issue du planning officiel ne peut pas être supprimée par une synchronisation individuelle';
  end if;

  if new.owner_id is distinct from auth.uid() then
    raise exception 'Une synchronisation individuelle ne peut modifier que votre propre planning';
  end if;

  -- A client-side reparse must never make an existing official guard disappear.
  if tg_op='UPDATE'
     and old.source_type='official_emergency'
     and old.deleted_at is null
     and new.deleted_at is not null then
    new.deleted_at := old.deleted_at;
  end if;

  -- Harmless refresh of the same official assignment is allowed.
  if tg_op='UPDATE'
     and old.source_type='official_emergency'
     and new.source_type='official_emergency'
     and new.owner_id is not distinct from old.owner_id
     and new.date_str is not distinct from old.date_str
     and new.shift_id is not distinct from old.shift_id
     and new.source_resource_id is not distinct from old.source_resource_id then
    return new;
  end if;

  if new.source_type <> 'official_emergency'
     or new.source_resource_id is null
     or new.source_resource_updated_at is null then
    raise exception 'Import officiel individuel invalide';
  end if;

  -- A disciplinary assignment can be created from the server-side
  -- disciplinary registry produced by the admin PDF analysis.
  select exists(
    select 1
    from public.official_disciplinary_guards g
    where g.owner_id=new.owner_id
      and g.date_str=new.date_str
      and g.shift_id=new.shift_id
      and g.resource_id=new.source_resource_id
      and g.resource_updated_at=new.source_resource_updated_at
  ) into v_allowed;

  if not v_allowed then
    v_allowed := public.official_unmatched_assignment_matches_profile(
      new.source_resource_id,
      new.source_resource_updated_at,
      new.owner_id,
      new.date_str,
      new.shift_id
    );
  end if;

  if not v_allowed then
    raise exception 'Cette affectation ne correspond pas au planning officiel enregistré par l’administrateur';
  end if;

  return new;
end;
$$;

revoke all on function public.protect_official_import_integrity()
  from public, anon, authenticated;

drop trigger if exists protect_official_import_integrity_trigger
  on public.planning_entries;

create trigger protect_official_import_integrity_trigger
before insert or update or delete on public.planning_entries
for each row execute function public.protect_official_import_integrity();
