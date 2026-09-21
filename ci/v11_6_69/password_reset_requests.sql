-- GardeFlow V11.6.69 - persistent password reset requests
-- Forgot-password requests become first-class admin notifications.

create table if not exists public.password_reset_requests (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  hospital text not null,
  status text not null default 'pending'
    check (status in ('pending','resolved')),
  requested_at timestamptz not null default now(),
  handled_at timestamptz,
  handled_by uuid references public.profiles(id) on delete set null
);

create unique index if not exists password_reset_requests_pending_profile_uidx
  on public.password_reset_requests(profile_id)
  where status='pending';

create index if not exists password_reset_requests_pending_hospital_idx
  on public.password_reset_requests(hospital, requested_at desc)
  where status='pending';

alter table public.password_reset_requests enable row level security;

revoke all on table public.password_reset_requests
  from public, anon, authenticated;
grant select on table public.password_reset_requests
  to authenticated;


create or replace function public.can_admin_handle_password_reset(
  p_hospital text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_admin()
     and (
       p_hospital = public.current_hospital()
       or not exists(
         select 1
         from public.profiles p
         where p.role='admin'
           and p.account_status='active'
           and p.hospital=p_hospital
       )
     );
$$;

revoke all on function public.can_admin_handle_password_reset(text)
  from public, anon;
grant execute on function public.can_admin_handle_password_reset(text)
  to authenticated;


drop policy if exists password_reset_requests_admin_select
  on public.password_reset_requests;

create policy password_reset_requests_admin_select
on public.password_reset_requests
for select to authenticated
using (
  status='pending'
  and public.can_admin_handle_password_reset(hospital)
);


create or replace function public.create_or_refresh_password_reset_request(
  p_profile_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_id uuid;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Accès refusé';
  end if;

  select * into v_profile
  from public.profiles
  where id=p_profile_id and account_status='active';

  if not found then
    raise exception 'Profil actif introuvable';
  end if;

  insert into public.password_reset_requests(
    profile_id,hospital,status,requested_at,handled_at,handled_by
  )
  values(
    v_profile.id,v_profile.hospital,'pending',now(),null,null
  )
  on conflict(profile_id) where status='pending'
  do update
     set hospital=excluded.hospital,
         requested_at=excluded.requested_at,
         handled_at=null,
         handled_by=null
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.create_or_refresh_password_reset_request(uuid)
  from public, anon, authenticated;
grant execute on function public.create_or_refresh_password_reset_request(uuid)
  to service_role;


create or replace function public.admin_password_reset_requests()
returns table(
  request_id uuid,
  profile_id uuid,
  requested_at timestamptz,
  full_name text,
  phone text,
  hospital text,
  service text,
  grade_label text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;

  return query
  select
    r.id,
    p.id,
    r.requested_at,
    trim(coalesce(p.prenom,'') || ' ' || coalesce(p.nom,'')),
    p.phone,
    p.hospital,
    p.service,
    case
      when p.medical_grade='senior' then 'Médecin senior'
      else 'Médecin junior'
    end
  from public.password_reset_requests r
  join public.profiles p on p.id=r.profile_id
  where r.status='pending'
    and p.account_status='active'
    and public.can_admin_handle_password_reset(r.hospital)
  order by r.requested_at desc;
end;
$$;

revoke all on function public.admin_password_reset_requests()
  from public, anon;
grant execute on function public.admin_password_reset_requests()
  to authenticated;


-- Realtime is used only as a wake-up signal. Row visibility is still RLS-scoped.
do $$
begin
  if not exists(
    select 1
    from pg_publication_tables
    where pubname='supabase_realtime'
      and schemaname='public'
      and tablename='password_reset_requests'
  ) then
    alter publication supabase_realtime add table public.password_reset_requests;
  end if;
end;
$$;
