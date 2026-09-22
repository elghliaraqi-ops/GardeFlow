-- GardeFlow V11.6.70
-- Calendrier des astreintes séniors + synchronisation des numéros validés
-- vers Annuaire > Médecins Séniors.

create or replace function public.normalize_ma_phone(p_phone text)
returns text
language sql
immutable
as $$
  select case
    when p_phone is null or btrim(p_phone) = '' then null
    else
      case
        when regexp_replace(p_phone, '[^0-9+]', '', 'g') like '+2120%'
          then '+212' || substring(regexp_replace(p_phone, '[^0-9]', '', 'g') from 5)
        when regexp_replace(p_phone, '[^0-9+]', '', 'g') like '+212%'
          then '+' || regexp_replace(p_phone, '[^0-9]', '', 'g')
        when regexp_replace(p_phone, '[^0-9]', '', 'g') like '212%'
          then '+' || regexp_replace(p_phone, '[^0-9]', '', 'g')
        when regexp_replace(p_phone, '[^0-9]', '', 'g') like '0%'
          and length(regexp_replace(p_phone, '[^0-9]', '', 'g')) = 10
          then '+212' || substring(regexp_replace(p_phone, '[^0-9]', '', 'g') from 2)
        else regexp_replace(p_phone, '[^0-9+]', '', 'g')
      end
  end
$$;

create table if not exists public.senior_oncall_assignments (
  id uuid primary key default gen_random_uuid(),
  hospital text not null,
  service text not null check (btrim(service) <> ''),
  duty_date date not null,
  senior_name text not null check (btrim(senior_name) <> ''),
  senior_phone text,
  source_resource_id uuid references public.shared_resources(id) on delete cascade,
  source_updated_at timestamptz,
  confidence numeric(5,4),
  validation_status text not null default 'draft'
    check (validation_status in ('draft','validated')),
  validated_by uuid references public.profiles(id) on delete set null,
  validated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists senior_oncall_date_hospital_service_idx
  on public.senior_oncall_assignments(duty_date, hospital, service);

create unique index if not exists senior_oncall_unique_assignment_idx
  on public.senior_oncall_assignments(
    hospital,
    service,
    duty_date,
    lower(btrim(senior_name))
  );

alter table public.senior_oncall_assignments enable row level security;

drop policy if exists senior_oncall_read on public.senior_oncall_assignments;
create policy senior_oncall_read
on public.senior_oncall_assignments
for select
to authenticated
using (
  auth.uid() is not null
  and public.current_account_active()
  and validation_status = 'validated'
);

drop policy if exists senior_oncall_admin_insert on public.senior_oncall_assignments;
create policy senior_oncall_admin_insert
on public.senior_oncall_assignments
for insert
to authenticated
with check (public.is_admin());

drop policy if exists senior_oncall_admin_update on public.senior_oncall_assignments;
create policy senior_oncall_admin_update
on public.senior_oncall_assignments
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists senior_oncall_admin_delete on public.senior_oncall_assignments;
create policy senior_oncall_admin_delete
on public.senior_oncall_assignments
for delete
to authenticated
using (public.is_admin());

grant select, insert, update, delete
on public.senior_oncall_assignments
to authenticated;

create or replace function public.senior_oncall_prepare_phone()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.senior_phone := public.normalize_ma_phone(new.senior_phone);
  new.updated_at := now();
  if new.validation_status = 'validated' and new.validated_at is null then
    new.validated_at := now();
    new.validated_by := coalesce(new.validated_by, auth.uid());
  end if;
  return new;
end;
$$;

drop trigger if exists senior_oncall_prepare_phone_trg
on public.senior_oncall_assignments;

create trigger senior_oncall_prepare_phone_trg
before insert or update
on public.senior_oncall_assignments
for each row execute function public.senior_oncall_prepare_phone();

create or replace function public.senior_oncall_sync_directory()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text;
begin
  if new.validation_status <> 'validated' then
    return new;
  end if;

  v_phone := public.normalize_ma_phone(new.senior_phone);
  if v_phone is null or btrim(v_phone) = '' then
    return new;
  end if;

  update public.directory_contacts
  set
    name = new.senior_name,
    service = new.service,
    phone = v_phone,
    updated_at = now()
  where category = 'medecins-seniors'
    and hospital = new.hospital
    and public.normalize_ma_phone(phone) = v_phone;

  if not found and not exists (
    select 1
    from public.directory_contacts d
    where d.hospital = new.hospital
      and public.normalize_ma_phone(d.phone) = v_phone
  ) then
    insert into public.directory_contacts(
      category, name, phone, hospital, service, created_by
    ) values (
      'medecins-seniors',
      new.senior_name,
      v_phone,
      new.hospital,
      new.service,
      new.validated_by
    );
  end if;

  return new;
end;
$$;

drop trigger if exists senior_oncall_sync_directory_trg
on public.senior_oncall_assignments;

create trigger senior_oncall_sync_directory_trg
after insert or update of
  validation_status, senior_phone, senior_name, service, hospital
on public.senior_oncall_assignments
for each row execute function public.senior_oncall_sync_directory();

create or replace function public.senior_oncall_roster(
  p_from date,
  p_to date
)
returns table(
  duty_date date,
  senior_name text,
  senior_phone text,
  service text,
  hospital text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    s.duty_date,
    s.senior_name,
    s.senior_phone,
    s.service,
    s.hospital
  from public.senior_oncall_assignments s
  where auth.uid() is not null
    and public.current_account_active()
    and p_from is not null
    and p_to is not null
    and p_from <= p_to
    and s.validation_status = 'validated'
    and s.duty_date between p_from and p_to
  order by s.duty_date, s.hospital, s.service, s.senior_name;
$$;

revoke all on function public.senior_oncall_roster(date,date)
  from public, anon;
grant execute on function public.senior_oncall_roster(date,date)
  to authenticated;

do $$ begin
  alter publication supabase_realtime
    add table public.senior_oncall_assignments;
exception when duplicate_object then null; end $$;
