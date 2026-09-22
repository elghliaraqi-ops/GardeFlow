-- GardeFlow v11.6.70
-- Astreintes séniors structurées à partir du fichier validé manuellement.

create table if not exists public.senior_oncall_rosters (
  id uuid primary key default gen_random_uuid(),
  hospital text not null,
  service text not null check (btrim(service) <> ''),
  senior_name text not null check (btrim(senior_name) <> ''),
  senior_phone text,
  duty_dates date[] not null default '{}',
  source_label text not null default 'manual',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (hospital, service, senior_name, source_label)
);

create index if not exists senior_oncall_rosters_hospital_service_idx
  on public.senior_oncall_rosters(hospital, service);

create index if not exists senior_oncall_rosters_dates_gin_idx
  on public.senior_oncall_rosters using gin(duty_dates);

alter table public.senior_oncall_rosters enable row level security;

drop policy if exists senior_oncall_rosters_read on public.senior_oncall_rosters;
create policy senior_oncall_rosters_read
on public.senior_oncall_rosters
for select
to authenticated
using (auth.uid() is not null and public.current_account_active());

drop policy if exists senior_oncall_rosters_admin_insert on public.senior_oncall_rosters;
create policy senior_oncall_rosters_admin_insert
on public.senior_oncall_rosters
for insert
to authenticated
with check (public.is_admin());

drop policy if exists senior_oncall_rosters_admin_update on public.senior_oncall_rosters;
create policy senior_oncall_rosters_admin_update
on public.senior_oncall_rosters
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists senior_oncall_rosters_admin_delete on public.senior_oncall_rosters;
create policy senior_oncall_rosters_admin_delete
on public.senior_oncall_rosters
for delete
to authenticated
using (public.is_admin());

grant select, insert, update, delete
on public.senior_oncall_rosters
to authenticated;

create or replace function public.senior_oncall_roster(
  p_from date,
  p_to date
)
returns table(
  date_str date,
  owner_name text,
  owner_phone text,
  service text,
  hospital text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    d::date as date_str,
    r.senior_name as owner_name,
    coalesce(r.senior_phone, '') as owner_phone,
    r.service,
    r.hospital
  from public.senior_oncall_rosters r
  cross join lateral unnest(r.duty_dates) as d
  where auth.uid() is not null
    and public.current_account_active()
    and p_from is not null
    and p_to is not null
    and p_from <= p_to
    and d between p_from and p_to
  order by d, r.hospital, r.service, r.senior_name;
$$;

revoke all on function public.senior_oncall_roster(date,date)
  from public, anon;
grant execute on function public.senior_oncall_roster(date,date)
  to authenticated;
