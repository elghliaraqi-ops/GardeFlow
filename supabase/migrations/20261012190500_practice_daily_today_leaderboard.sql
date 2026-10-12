-- Add a genuine Casablanca-today podium without changing past official /10 results.
-- Only immutable first daily attempts contribute, with the same opt-in privacy rule.
create or replace function public.practice_daily_game_leaderboard(
  p_period text default 'month',
  p_limit integer default 30
)
returns table(
  rank bigint,
  user_id uuid,
  display_name text,
  hospital text,
  xp bigint,
  completed_days bigint,
  perfect_days bigint
)
language plpgsql stable security definer
set search_path=public,pg_temp
as $$
declare v_today date:=(now() at time zone 'Africa/Casablanca')::date;
begin
  if auth.uid() is null or not exists(
    select 1 from public.profiles p
    where p.id=auth.uid() and p.account_status='active'
  ) then raise exception 'active_account_required';end if;
  if p_period not in ('day','month','all') or p_limit is null
     or p_limit<1 or p_limit>100 then raise exception 'invalid_leaderboard_parameters';end if;
  return query
  with scores as (
    select a.user_id,
      sum(public.practice_daily_award_xp(a.score))::bigint total_xp,
      count(*)::bigint days,
      count(*) filter(where a.score=10)::bigint perfect
    from public.practice_daily_attempts a
    where p_period='all'
       or (p_period='month' and a.challenge_date>=date_trunc('month',v_today)::date)
       or (p_period='day' and a.challenge_date=v_today)
    group by a.user_id
  ), eligible as (
    select s.user_id,s.total_xp,s.days,s.perfect,
       trim(concat_ws(' ','Dr',nullif(p.prenom,''),nullif(p.nom,''))) name,
       p.hospital
    from scores s
    join public.profiles p on p.id=s.user_id and p.account_status='active'
    left join public.practice_preferences pref on pref.user_id=p.id
    where coalesce(pref.leaderboard_opt_in,true)
  )
  select row_number() over(
    order by e.total_xp desc,e.days desc,e.perfect desc,e.user_id
   )::bigint,e.user_id,e.name,e.hospital,e.total_xp,e.days,e.perfect
  from eligible e
  order by e.total_xp desc,e.days desc,e.perfect desc,e.user_id
  limit p_limit;
end;
$$;

revoke all on function public.practice_daily_game_leaderboard(text,integer) from public,anon;
grant execute on function public.practice_daily_game_leaderboard(text,integer) to authenticated;
