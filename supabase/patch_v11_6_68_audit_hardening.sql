-- GardeFlow V11.6.68 - audit hardening
-- Idempotent security + past-month read-only protections.

begin;

-- ---------------------------------------------------------------------------
-- 0) Legacy astreinte objects required by the hardening below.
-- Keep this patch replayable on a fresh database.
-- ---------------------------------------------------------------------------

create table if not exists public.astreinte_photos (
  id text primary key,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  owner_phone text not null default '',
  owner_name text not null default '',
  storage_path text not null unique,
  original_name text not null default '',
  created_at timestamptz not null default now()
);

alter table public.astreinte_photos enable row level security;

create or replace function public.fill_astreinte_photo_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $
declare
  p public.profiles%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Session requise';
  end if;

  select * into p
  from public.profiles
  where id=auth.uid() and account_status='active';

  if not found then
    raise exception 'Profil actif introuvable';
  end if;

  new.owner_id := auth.uid();
  new.owner_phone := coalesce(p.phone,'');
  new.owner_name := trim(coalesce(p.prenom,'') || ' ' || coalesce(p.nom,''));
  return new;
end;
$;

revoke all on function public.fill_astreinte_photo_owner()
  from public, anon, authenticated;

drop trigger if exists astreinte_photos_fill_owner on public.astreinte_photos;
create trigger astreinte_photos_fill_owner
before insert on public.astreinte_photos
for each row execute function public.fill_astreinte_photo_owner();

insert into storage.buckets(id,name,public)
values('astreinte-photos','astreinte-photos',false)
on conflict(id) do update set public=false;


-- ---------------------------------------------------------------------------
-- 1) Absolute server-side read-only rule for past months.
-- ---------------------------------------------------------------------------

create or replace function public.guardeflow_is_past_month(p_date date)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select date_trunc('month', p_date)::date
       < date_trunc('month', current_date)::date
$$;

revoke all on function public.guardeflow_is_past_month(date) from public, anon;
grant execute on function public.guardeflow_is_past_month(date) to authenticated, service_role;

create or replace function public.protect_past_month_planning_entry()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_old_past boolean := false;
  v_new_past boolean := false;
begin
  if tg_op <> 'INSERT' then
    v_old_past := public.guardeflow_is_past_month(old.date_str);
  end if;
  if tg_op <> 'DELETE' then
    v_new_past := public.guardeflow_is_past_month(new.date_str);
  end if;

  -- Trusted maintenance may remove historical data as part of a full
  -- account deletion. Human/admin sessions remain read-only.
  if coalesce(auth.jwt()->>'role','') = 'service_role' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if v_old_past or v_new_past then
    raise exception 'Mois passé : le planning est en lecture seule et ne peut plus être modifié.';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.protect_past_month_planning_entry() from public, anon, authenticated;
grant execute on function public.protect_past_month_planning_entry() to service_role;

drop trigger if exists protect_past_month_planning_entry_trigger
  on public.planning_entries;

create trigger protect_past_month_planning_entry_trigger
before insert or update or delete on public.planning_entries
for each row execute function public.protect_past_month_planning_entry();

-- planning_months is also immutable once its calendar month is over.
-- Returning NULL makes internal/cron attempts a no-op instead of breaking a whole
-- scheduled batch, while user-facing RPCs already raise explicit errors.
create or replace function public.protect_past_planning_month()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_year integer;
  v_month integer;
  v_first_day date;
begin
  if tg_op = 'DELETE' then
    v_year := old.year;
    v_month := old.month;
  else
    v_year := new.year;
    v_month := new.month;
  end if;

  v_first_day := make_date(v_year, v_month, 1);

  if coalesce(auth.jwt()->>'role','') = 'service_role' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if v_first_day < date_trunc('month', current_date)::date then
    return null;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.protect_past_planning_month() from public, anon, authenticated;
grant execute on function public.protect_past_planning_month() to service_role;

drop trigger if exists protect_past_planning_month_trigger
  on public.planning_months;

create trigger protect_past_planning_month_trigger
before insert or update or delete on public.planning_months
for each row execute function public.protect_past_planning_month();

-- ---------------------------------------------------------------------------
-- 2) "Redo overlay" must be false for past months as well as approved months.
-- ---------------------------------------------------------------------------

create or replace function public.official_roster_my_summary(
  p_resource_id uuid,
  p_resource_updated_at timestamp with time zone
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
  main_month_start date;
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
    main_month_start := make_date(main_year, main_month, 1);
    can_resync :=
      main_month_start >= date_trunc('month', current_date)::date
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

revoke execute on function public.official_roster_my_summary(uuid,timestamp with time zone)
  from public, anon;
grant execute on function public.official_roster_my_summary(uuid,timestamp with time zone)
  to authenticated, service_role;

create or replace function public.reset_my_official_roster_profile_sync(
  p_resource_id uuid,
  p_resource_updated_at timestamp with time zone
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
  main_month_start date;
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

  main_month_start := make_date(main_year, main_month, 1);

  if main_month_start < date_trunc('month', current_date)::date then
    raise exception 'Mois passé : la superposition est définitivement en lecture seule.';
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

revoke execute on function public.reset_my_official_roster_profile_sync(uuid,timestamp with time zone)
  from public, anon;
grant execute on function public.reset_my_official_roster_profile_sync(uuid,timestamp with time zone)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) Legacy astreinte surface: administration only for writes.
-- ---------------------------------------------------------------------------

drop policy if exists astreinte_photos_insert on public.astreinte_photos;
drop policy if exists astreinte_photos_delete on public.astreinte_photos;
drop policy if exists astreinte_photos_select on public.astreinte_photos;
drop policy if exists astreinte_photos_update on public.astreinte_photos;

create policy astreinte_photos_select
on public.astreinte_photos
for select
to authenticated
using ((select auth.uid()) is not null and public.current_account_active());

create policy astreinte_photos_insert
on public.astreinte_photos
for insert
to authenticated
with check (
  public.is_admin()
  and owner_id = (select auth.uid())
);

create policy astreinte_photos_update
on public.astreinte_photos
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy astreinte_photos_delete
on public.astreinte_photos
for delete
to authenticated
using (public.is_admin());

drop policy if exists astreinte_storage_insert on storage.objects;
drop policy if exists astreinte_storage_update on storage.objects;
drop policy if exists astreinte_storage_delete on storage.objects;
drop policy if exists astreinte_storage_select on storage.objects;

create policy astreinte_storage_select
on storage.objects
for select
to authenticated
using (
  bucket_id='astreinte-photos'
  and public.current_account_active()
);

create policy astreinte_storage_insert
on storage.objects
for insert
to authenticated
with check (
  bucket_id='astreinte-photos'
  and public.is_admin()
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy astreinte_storage_update
on storage.objects
for update
to authenticated
using (
  bucket_id='astreinte-photos'
  and public.is_admin()
)
with check (
  bucket_id='astreinte-photos'
  and public.is_admin()
);

create policy astreinte_storage_delete
on storage.objects
for delete
to authenticated
using (
  bucket_id='astreinte-photos'
  and public.is_admin()
);

-- Tighten the current shared-resource read policies to active accounts.
drop policy if exists shared_resources_read on public.shared_resources;
create policy shared_resources_read
on public.shared_resources
for select
to authenticated
using (public.current_account_active());

drop policy if exists gardeflow_shared_read on storage.objects;
create policy gardeflow_shared_read
on storage.objects
for select
to authenticated
using (
  bucket_id='gardeflow-shared'
  and public.current_account_active()
);

-- ---------------------------------------------------------------------------
-- 4) SECURITY DEFINER hardening.
-- Remove implicit PUBLIC/anon execution and direct execution of trigger-only
-- helpers. Client-facing RPCs retain their explicit authenticated grants.
-- ---------------------------------------------------------------------------

revoke execute on function public.apply_current_disciplinary_rules_for_me() from public, anon;
revoke execute on function public.import_official_emergency_roster(uuid,timestamp with time zone,jsonb,jsonb) from public, anon;
revoke execute on function public.import_official_emergency_roster_for_profile(uuid,timestamp with time zone,uuid,jsonb,jsonb) from public, anon;
revoke execute on function public.junior_oncall_roster(date,date) from public, anon;
revoke execute on function public.official_roster_my_summary(uuid,timestamp with time zone) from public, anon;
revoke execute on function public.register_official_disciplinary_marks(uuid,timestamp with time zone,jsonb) from public, anon;
revoke execute on function public.reset_my_official_roster_profile_sync(uuid,timestamp with time zone) from public, anon;

-- Trigger/internal-only functions must never be callable as public RPCs.
revoke execute on function public.detach_official_source_on_owner_edit()
  from public, anon, authenticated;
revoke execute on function public.fill_astreinte_photo_owner()
  from public, anon, authenticated;
revoke execute on function public.fill_exchange_identity()
  from public, anon, authenticated;
revoke execute on function public.handle_new_user()
  from public, anon, authenticated;
revoke execute on function public.normalize_v11_6_51_roster_revision()
  from public, anon, authenticated;
revoke execute on function public.protect_disciplinary_guard()
  from public, anon, authenticated;
revoke execute on function public.protect_locked_planning()
  from public, anon, authenticated;
revoke execute on function public.reject_disciplinary_exchange_request()
  from public, anon, authenticated;
revoke execute on function public.sync_disciplinary_registry_from_entry()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5) Covering indexes identified by the production performance advisor.
-- ---------------------------------------------------------------------------

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

create index if not exists push_tokens_owner_id_idx
  on public.push_tokens(owner_id);

create index if not exists shared_resources_uploaded_by_idx
  on public.shared_resources(uploaded_by);

create index if not exists profiles_hospital_status_idx
  on public.profiles(hospital,account_status);

create index if not exists profiles_hospital_service_status_idx
  on public.profiles(hospital,service,account_status);

commit;
