-- Server-only lock: ensure concurrent users do not pay for parallel AI generations.
create table if not exists public.practice_daily_generation_claims(
 challenge_date date not null,
 mode text not null check(mode in('cours','cas_clinique')),
 claimed_at timestamptz not null default now(),
 primary key(challenge_date,mode)
);
alter table public.practice_daily_generation_claims enable row level security;
revoke all on public.practice_daily_generation_claims from public,anon,authenticated;

create or replace function public.practice_daily_generation_claim(p_day date,p_mode text)
returns boolean language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_count integer;
begin
 if p_day is distinct from (now() at time zone 'Africa/Casablanca')::date or
 p_mode not in ('cours','cas_clinique') then return false;end if;
 if exists(select 1 from public.practice_daily_challenges where challenge_date=p_day and mode=p_mode)then return false;end if;
 insert into public.practice_daily_generation_claims(challenge_date,mode,claimed_at)
 values(p_day,p_mode,now())
 on conflict(challenge_date,mode) do update set claimed_at=excluded.claimed_at
 where public.practice_daily_generation_claims.claimed_at < now()-interval '3 minutes';
 get diagnostics v_count=row_count;
 return v_count=1;
end;$$;
revoke all on function public.practice_daily_generation_claim(date,text) from public,anon,authenticated;
grant execute on function public.practice_daily_generation_claim(date,text) to service_role;
