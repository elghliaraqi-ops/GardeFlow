-- GardeFlow V11.6.69 - RLS init-plan performance hardening
-- Preserve policy semantics while evaluating session helpers once per query.

create index if not exists password_reset_requests_handled_by_idx
  on public.password_reset_requests(handled_by);

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
for select to authenticated
using (
  id=(select auth.uid())
  or (select public.is_admin())
  or (
    (select public.current_account_active())
    and account_status='active'
    and hospital=(select public.current_hospital())
  )
);

drop policy if exists leave_select on public.leave_requests;
create policy leave_select on public.leave_requests
for select to authenticated
using (
  (select public.is_admin())
  or (
    (select public.current_account_active())
    and owner_id=(select auth.uid())
  )
);

drop policy if exists exchange_select on public.exchange_requests;
create policy exchange_select on public.exchange_requests
for select to authenticated
using (
  (select public.is_admin())
  or (
    (select public.current_account_active())
    and (
      from_id=(select auth.uid())
      or to_id=(select auth.uid())
    )
  )
);

drop policy if exists planning_months_select on public.planning_months;
create policy planning_months_select on public.planning_months
for select to authenticated
using (
  owner_id=(select auth.uid())
  or (select public.is_admin())
);

drop policy if exists planning_select on public.planning_entries;
create policy planning_select on public.planning_entries
for select to authenticated
using (
  (select public.is_admin())
  or owner_id=(select auth.uid())
  or (
    (select public.current_account_active())
    and public.planning_month_is_approved(owner_id,date_str)
    and (
      shift_id<>'conge'
      or public.leave_request_is_approved(leave_request_id)
    )
    and exists(
      select 1
      from public.profiles p
      where p.id=planning_entries.owner_id
        and p.account_status='active'
        and p.hospital=(select public.current_hospital())
    )
  )
);

drop policy if exists exchange_insert on public.exchange_requests;
create policy exchange_insert on public.exchange_requests
for insert to authenticated
with check (
  (select public.current_account_active())
  and from_id=(select auth.uid())
  and from_id<>to_id
  and status='pendingB'
  and exists(
    select 1
    from public.profiles a
    join public.profiles b on true
    where a.id=exchange_requests.from_id
      and b.id=exchange_requests.to_id
      and a.account_status='active'
      and b.account_status='active'
      and a.hospital=b.hospital
  )
  and exists(
    select 1
    from public.planning_entries s
    where s.id=exchange_requests.planning_entry_id
      and s.owner_id=exchange_requests.from_id
      and s.deleted_at is null
      and s.shift_id<>'conge'
      and s.date_str=exchange_requests.date_str
      and s.shift_id=exchange_requests.shift_id
      and not public.guard_has_started(s.date_str,s.shift_id)
  )
  and (
    type='transfer'
    or (
      type='exchange'
      and exists(
        select 1
        from public.planning_entries t
        where t.id=exchange_requests.target_planning_entry_id
          and t.owner_id=exchange_requests.to_id
          and t.deleted_at is null
          and t.shift_id<>'conge'
          and t.date_str=exchange_requests.target_date_str
          and t.shift_id=exchange_requests.target_shift_id
          and not public.guard_has_started(t.date_str,t.shift_id)
      )
      and (
        not (
          exchange_requests.shift_id like 'service-%'
          or exchange_requests.target_shift_id like 'service-%'
        )
        or exists(
          select 1
          from public.profiles a
          join public.profiles b on true
          where a.id=exchange_requests.from_id
            and b.id=exchange_requests.to_id
            and nullif(trim(a.service),'') is not null
            and nullif(trim(b.service),'') is not null
            and trim(a.service)=trim(b.service)
        )
      )
    )
  )
);

drop policy if exists directory_contacts_admin_insert on public.directory_contacts;
create policy directory_contacts_admin_insert on public.directory_contacts
for insert to authenticated
with check (
  (select public.is_admin())
  and created_by=(select auth.uid())
);

drop policy if exists directory_contacts_read on public.directory_contacts;
create policy directory_contacts_read on public.directory_contacts
for select to authenticated
using (
  (select auth.uid()) is not null
  and (select public.current_account_active())
);

drop policy if exists official_roster_profile_sync_read
  on public.official_roster_profile_sync;
create policy official_roster_profile_sync_read
on public.official_roster_profile_sync
for select to authenticated
using (
  profile_id=(select auth.uid())
  or (select public.is_admin())
);

drop policy if exists shared_resources_admin_insert on public.shared_resources;
create policy shared_resources_admin_insert on public.shared_resources
for insert to authenticated
with check (
  (select public.is_admin())
  and uploaded_by=(select auth.uid())
);

drop policy if exists shared_resources_admin_update on public.shared_resources;
create policy shared_resources_admin_update on public.shared_resources
for update to authenticated
using ((select public.is_admin()))
with check (
  (select public.is_admin())
  and uploaded_by=(select auth.uid())
);
