-- GardeFlow V11.6.68 - audit hardening
-- 1) Past months are immutable at database level, regardless of Flutter/RPC path.
-- 2) Legacy astreinte write paths become admin-only.
-- 3) SECURITY DEFINER helpers are no longer anonymously executable.
-- 4) Add missing indexes used by common RLS / foreign-key paths.

create or replace function public.protect_past_planning_entries()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  month_start date := date_trunc('month', current_date)::date;
begin
  -- Trusted server maintenance (for example account deletion) may clean up
  -- historical rows. Human/API sessions remain strictly read-only.
  if auth.role() = 'service_role' then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;

  if tg_op = 'INSERT' then
    if new.date_str < month_start then
      raise exception 'Un mois passé est en lecture seule';
    end if;
    return new;
  end if;

  if old.date_str < month_start then
    raise exception 'Un mois passé est en lecture seule';
  end if;

  if tg_op = 'UPDATE' and new.date_str < month_start then
    raise exception 'Une garde ne peut pas être déplacée vers un mois passé';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.protect_past_planning_entries()
  from public, anon, authenticated;

drop trigger if exists protect_past_planning_entries_trigger
  on public.planning_entries;

create trigger protect_past_planning_entries_trigger
before insert or update or delete on public.planning_entries
for each row execute function public.protect_past_planning_entries();


-- "Refaire la superposition" is unavailable for an already-approved OR past month.
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
  main_month_date date;
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

  select m.year,m.month into main_year,main_month
  from public.official_roster_resource_main_month(
    p_resource_id,
    p_resource_updated_at
  ) m;

  if main_year is null or main_month is null then
    raise exception 'Impossible d’identifier le mois principal de ce planning officiel';
  end if;

  main_month_date := make_date(main_year, main_month, 1);
  if main_month_date < date_trunc('month',current_date)::date then
    raise exception 'Un mois passé est en lecture seule : la superposition ne peut plus être refaite.';
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

revoke execute on function public.reset_my_official_roster_profile_sync(uuid,timestamptz)
  from public, anon;
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
  main_month_date date;
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

  select m.year,m.month into main_year,main_month
  from public.official_roster_resource_main_month(
    p_resource_id,
    p_resource_updated_at
  ) m;

  if main_year is not null and main_month is not null then
    main_month_date := make_date(main_year,main_month,1);
    can_resync :=
      main_month_date >= date_trunc('month',current_date)::date
      and not exists(
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

revoke execute on function public.official_roster_my_summary(uuid,timestamptz)
  from public, anon;
grant execute on function public.official_roster_my_summary(uuid,timestamptz)
  to authenticated;


-- Disciplinary auto-application must never rewrite historical months.
create or replace function public.apply_current_disciplinary_rules_for_me()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  p public.profiles%rowtype;
  m record;
  existing public.planning_entries%rowtype;
  inserted_count int := 0;
  updated_count int := 0;
  matched_rules int := 0;
begin
  if uid is null then raise exception 'Session requise'; end if;

  select * into p
  from public.profiles
  where id=uid and account_status='active'
  for update;

  if not found then raise exception 'Profil actif introuvable'; end if;

  perform set_config('gardeflow.official_import','1',true);

  for m in
    select
      r.date_str,
      r.shift_id,
      r.resource_id,
      r.resource_updated_at
    from public.official_disciplinary_name_rules r
    join public.shared_resources sr
      on sr.id=r.resource_id
     and sr.kind='official_pdf'
     and sr.updated_at=r.resource_updated_at
    where r.date_str >= date_trunc('month',current_date)::date
      and public.profile_matches_disciplinary_rule(uid,r.date_str,r.normalized_red_text)
      and (
        (sr.slot='hm6_bouskoura' and p.hospital='Hôpital Universitaire International Mohammed VI de Bouskoura')
        or (sr.slot='hm6_rabat' and p.hospital='Hôpital Universitaire International Mohammed VI de Rabat')
        or (sr.slot='hck_casa' and p.hospital='Hôpital Universitaire International Cheikh Khalifa de Casablanca')
      )
    order by r.date_str
  loop
    matched_rules := matched_rules + 1;

    insert into public.official_disciplinary_guards(
      owner_id,date_str,shift_id,resource_id,resource_updated_at,detected_at
    )
    values(
      uid,m.date_str,m.shift_id,m.resource_id,m.resource_updated_at,now()
    )
    on conflict(owner_id,date_str,resource_id,resource_updated_at)
    do update
      set shift_id=excluded.shift_id,
          detected_at=now();

    select * into existing
    from public.planning_entries
    where owner_id=uid
      and date_str=m.date_str
      and deleted_at is null
    order by created_at desc
    limit 1
    for update;

    if found then
      update public.exchange_requests
      set status='cancelled'
      where status in ('pendingB','pendingAdmin')
        and (
          planning_entry_id=existing.id
          or target_planning_entry_id=existing.id
        );

      update public.planning_entries
      set shift_id=m.shift_id,
          owner_phone=p.phone,
          owner_name=trim(coalesce(p.prenom,'') || ' ' || coalesce(p.nom,'')),
          leave_request_id=null,
          source_type='official_emergency',
          source_resource_id=m.resource_id,
          source_resource_updated_at=m.resource_updated_at,
          is_disciplinary=true
      where id=existing.id;

      updated_count := updated_count + 1;
    else
      insert into public.planning_entries(
        id,date_str,shift_id,owner_id,owner_phone,owner_name,created_at,
        source_type,source_resource_id,source_resource_updated_at,is_disciplinary
      )
      values(
        'pdf-' || replace(gen_random_uuid()::text,'-',''),
        m.date_str,m.shift_id,uid,p.phone,
        trim(coalesce(p.prenom,'') || ' ' || coalesce(p.nom,'')),
        now(),
        'official_emergency',m.resource_id,m.resource_updated_at,true
      );

      inserted_count := inserted_count + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'matched_rules',matched_rules,
    'inserted',inserted_count,
    'updated',updated_count
  );
end;
$$;

revoke execute on function public.apply_current_disciplinary_rules_for_me()
  from public, anon;
grant execute on function public.apply_current_disciplinary_rules_for_me()
  to authenticated;


-- Legacy astreinte table/bucket: read remains authenticated, all writes become admin-only.
drop policy if exists astreinte_photos_insert on public.astreinte_photos;
drop policy if exists astreinte_photos_delete on public.astreinte_photos;

create policy astreinte_photos_insert
on public.astreinte_photos
for insert to authenticated
with check (public.is_admin() and owner_id = (select auth.uid()));

create policy astreinte_photos_delete
on public.astreinte_photos
for delete to authenticated
using (public.is_admin());

drop policy if exists astreinte_storage_insert on storage.objects;
drop policy if exists astreinte_storage_delete on storage.objects;

create policy astreinte_storage_insert
on storage.objects
for insert to authenticated
with check (
  bucket_id = 'astreinte-photos'
  and public.is_admin()
);

create policy astreinte_storage_delete
on storage.objects
for delete to authenticated
using (
  bucket_id = 'astreinte-photos'
  and public.is_admin()
);


-- Remove anonymous/public execution from every SECURITY DEFINER function in public.
do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.prosecdef
  loop
    execute format('revoke execute on function %s from public, anon', f.signature);
  end loop;
end;
$$;

-- Trigger-only helpers do not need direct authenticated RPC access.
revoke execute on function public.protect_disciplinary_guard() from authenticated;
revoke execute on function public.protect_locked_planning() from authenticated;
revoke execute on function public.protect_past_planning_entries() from authenticated;
revoke execute on function public.fill_exchange_identity() from authenticated;
revoke execute on function public.fill_astreinte_photo_owner() from authenticated;
revoke execute on function public.handle_new_user() from authenticated;
revoke execute on function public.detach_official_source_on_owner_edit() from authenticated;
revoke execute on function public.normalize_v11_6_51_roster_revision() from authenticated;
revoke execute on function public.reject_disciplinary_exchange_request() from authenticated;
revoke execute on function public.sync_disciplinary_registry_from_entry() from authenticated;


-- Missing indexes highlighted during audit.
create index if not exists audit_log_actor_id_idx
  on public.audit_log(actor_id);
create index if not exists directory_contacts_created_by_idx
  on public.directory_contacts(created_by);
create index if not exists exchange_requests_planning_entry_id_idx
  on public.exchange_requests(planning_entry_id);
create index if not exists exchange_requests_target_planning_entry_id_idx
  on public.exchange_requests(target_planning_entry_id);
create index if not exists leave_requests_planning_entry_id_idx
  on public.leave_requests(planning_entry_id);
create index if not exists official_disciplinary_guards_resource_id_idx
  on public.official_disciplinary_guards(resource_id);
create index if not exists official_roster_import_runs_imported_by_idx
  on public.official_roster_import_runs(imported_by);
create index if not exists planning_auto_validation_events_resource_id_idx
  on public.planning_auto_validation_events(resource_id);
create index if not exists planning_months_reviewed_by_idx
  on public.planning_months(reviewed_by);
create index if not exists shared_resources_uploaded_by_idx
  on public.shared_resources(uploaded_by);
create index if not exists profiles_hospital_status_idx
  on public.profiles(hospital,account_status);
create index if not exists profiles_hospital_service_status_idx
  on public.profiles(hospital,service,account_status);
