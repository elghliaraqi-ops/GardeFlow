-- GardeFlow V11.6.68 - password reset notification rate limiting
create table if not exists public.password_reset_rate_limits (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  last_requested_at timestamptz not null default now()
);

alter table public.password_reset_rate_limits enable row level security;
revoke all on table public.password_reset_rate_limits from public, anon, authenticated;

create or replace function public.claim_password_reset_notification(
  p_profile_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_last timestamptz;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Accès refusé';
  end if;

  select last_requested_at
    into v_last
  from public.password_reset_rate_limits
  where profile_id = p_profile_id
  for update;

  if found and v_last > now() - interval '5 minutes' then
    return false;
  end if;

  insert into public.password_reset_rate_limits(profile_id,last_requested_at)
  values(p_profile_id,now())
  on conflict(profile_id)
  do update set last_requested_at=excluded.last_requested_at;

  return true;
end;
$$;

revoke all on function public.claim_password_reset_notification(uuid)
  from public, anon, authenticated;
grant execute on function public.claim_password_reset_notification(uuid)
  to service_role;
