-- GardeFlow V12 production hardening baseline
-- Captures the production fixes applied on 2026-09-23 so the repository and
-- deployed Supabase business rules remain aligned.

create or replace function public.protect_past_planning_month()
returns trigger
language plpgsql
set search_path to 'public'
as $$
declare
  v_year integer;
  v_month integer;
  v_first_day date;
begin
  -- Auth/service maintenance must be able to cascade dependent planning rows
  -- when an account is permanently removed. Normal users remain read-only.
  if current_user in ('supabase_auth_admin', 'service_role', 'postgres')
     or coalesce(auth.jwt()->>'role','') = 'service_role' then
    if tg_op = 'DELETE' then
      return old;
    else
      return new;
    end if;
  end if;

  if tg_op = 'DELETE' then
    v_year := old.year;
    v_month := old.month;
  else
    v_year := new.year;
    v_month := new.month;
  end if;

  v_first_day := make_date(v_year, v_month, 1);
  if v_first_day < date_trunc('month', current_date)::date then
    raise exception
      'Mois passé : le calendrier est en lecture seule et ne peut plus être modifié.';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

-- Keep official-roster synchronization on the exact revision produced by the
-- V11.6.70 import functions that form the V12 backend baseline.
create or replace function public.official_roster_import_is_current(
  p_resource_id uuid,
  p_resource_updated_at timestamptz
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;
  return exists(
    select 1
    from public.official_roster_import_runs r
    where r.resource_id = p_resource_id
      and r.resource_updated_at = p_resource_updated_at
      and r.sync_revision = 'v11.6.70-r1'
  );
end;
$$;

create or replace function public.official_roster_profile_sync_is_current(
  p_resource_id uuid,
  p_resource_updated_at timestamptz,
  p_profile_id uuid
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_profile public.profiles%rowtype;
  v_signature text;
  v_revision constant text := 'v11.6.70-r1';
begin
  if auth.uid() is null then raise exception 'Session requise'; end if;
  if p_profile_id <> auth.uid() and not public.is_admin() then
    raise exception 'Accès refusé';
  end if;

  select * into v_profile
  from public.profiles p
  where p.id = p_profile_id and p.account_status = 'active';
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
      and ps.sync_revision = v_revision
  );
end;
$$;

-- Cover the public_announcements author FK and retain the optimized RLS forms
-- where auth/helper calls are evaluated once per statement rather than per row.
create index if not exists public_announcements_author_id_idx
  on public.public_announcements(author_id);

drop policy if exists public_announcements_insert on public.public_announcements;
create policy public_announcements_insert
on public.public_announcements
for insert
to authenticated
with check (
  (select public.current_account_active())
  and author_id = (select auth.uid())
  and closed_at is null
  and exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.account_status = 'active'
      and p.hospital = public_announcements.hospital
      and not (p.promotion_number is distinct from public_announcements.promotion_number)
  )
  and exists (
    select 1 from public.planning_entries e
    where e.id = public_announcements.planning_entry_id
      and e.owner_id = (select auth.uid())
      and e.deleted_at is null
      and e.shift_id <> 'conge'
      and coalesce(e.is_disciplinary,false) = false
      and e.date_str = public_announcements.date_str
      and e.shift_id = public_announcements.shift_id
      and not public.guard_has_started(e.date_str,e.shift_id)
      and public.planning_month_is_approved(e.owner_id,e.date_str)
  )
);

drop policy if exists public_announcements_update on public.public_announcements;
create policy public_announcements_update
on public.public_announcements
for update
to authenticated
using (
  (select public.current_account_active())
  and (author_id = (select auth.uid()) or (select public.is_admin()))
)
with check (
  (select public.current_account_active())
  and (author_id = (select auth.uid()) or (select public.is_admin()))
);

drop policy if exists public_announcements_delete on public.public_announcements;
create policy public_announcements_delete
on public.public_announcements
for delete
to authenticated
using (
  (select public.current_account_active())
  and (author_id = (select auth.uid()) or (select public.is_admin()))
);

drop policy if exists shared_resources_admin_update on public.shared_resources;
create policy shared_resources_admin_update
on public.shared_resources
for update
to authenticated
using ((select public.is_admin()))
with check (
  (select public.is_admin())
  and uploaded_by = (select auth.uid())
);

drop policy if exists senior_oncall_rosters_read on public.senior_oncall_rosters;
create policy senior_oncall_rosters_read
on public.senior_oncall_rosters
for select
to authenticated
using (
  (select auth.uid()) is not null
  and (select public.current_account_active())
);
