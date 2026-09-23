-- GardeFlow audit optimizations — 2026-09-23
-- Production migration already applied to Supabase project PlanningHM6.
-- Purpose: preserve the production schema fix in Git and make it reproducible.

create index if not exists public_announcements_author_id_idx
  on public.public_announcements(author_id);

alter policy public_announcements_insert on public.public_announcements
with check (
  (select public.current_account_active())
  and author_id = (select auth.uid())
  and closed_at is null
  and exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.account_status='active'
      and p.hospital = public_announcements.hospital
      and not (p.promotion_number is distinct from public_announcements.promotion_number)
  )
  and exists (
    select 1 from public.planning_entries e
    where e.id = public_announcements.planning_entry_id
      and e.owner_id = (select auth.uid())
      and e.deleted_at is null
      and e.shift_id <> 'conge'
      and coalesce(e.is_disciplinary,false)=false
      and e.date_str = public_announcements.date_str
      and e.shift_id = public_announcements.shift_id
      and not public.guard_has_started(e.date_str,e.shift_id)
      and public.planning_month_is_approved(e.owner_id,e.date_str)
  )
);

alter policy public_announcements_update on public.public_announcements
using (
  (select public.current_account_active())
  and (author_id = (select auth.uid()) or (select public.is_admin()))
)
with check (
  (select public.current_account_active())
  and (author_id = (select auth.uid()) or (select public.is_admin()))
);

alter policy public_announcements_delete on public.public_announcements
using (
  (select public.current_account_active())
  and (author_id = (select auth.uid()) or (select public.is_admin()))
);

alter policy shared_resources_admin_update on public.shared_resources
using ((select public.is_admin()))
with check ((select public.is_admin()) and uploaded_by = (select auth.uid()));

alter policy senior_oncall_rosters_read on public.senior_oncall_rosters
using ((select auth.uid()) is not null and (select public.current_account_active()));

create or replace function public.official_roster_import_is_current(
  p_resource_id uuid,
  p_resource_updated_at timestamptz
) returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_admin() then raise exception 'Réservé à l’administrateur'; end if;
  return exists(
    select 1 from public.official_roster_import_runs r
    where r.resource_id=p_resource_id
      and r.resource_updated_at=p_resource_updated_at
      and r.sync_revision='v11.6.70-r1'
  );
end;
$function$;

create or replace function public.official_roster_profile_sync_is_current(
  p_resource_id uuid,
  p_resource_updated_at timestamptz,
  p_profile_id uuid
) returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
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
    select 1 from public.official_roster_profile_sync ps
    where ps.resource_id = p_resource_id
      and ps.resource_updated_at = p_resource_updated_at
      and ps.profile_id = p_profile_id
      and ps.profile_signature = v_signature
      and ps.sync_revision = v_revision
  );
end;
$function$;

create or replace function public.request_daily_news_refresh()
returns bigint
language plpgsql
security definer
set search_path to 'public','extensions','net'
as $function$
declare
  v_last_sync timestamptz;
  v_role text := coalesce(auth.jwt()->>'role','');
begin
  if v_role <> 'service_role' and not public.current_account_active() then
    raise exception 'Compte actif requis';
  end if;

  select last_sync_at into v_last_sync
  from public.daily_news_config
  where id=true;

  if v_last_sync is not null and v_last_sync > now() - interval '60 seconds' then
    return 0;
  end if;

  return public.invoke_daily_news_sync();
end;
$function$;
