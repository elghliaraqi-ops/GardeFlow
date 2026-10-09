-- Daily Practice gamification is derived exclusively from immutable first attempts.
-- Replays, clinical documentation XP, and ordinary QCM rankings are unaffected.
create or replace function public.practice_daily_award_xp(p_score integer)
returns integer
language sql immutable strict
set search_path=public,pg_temp
as $$
  select case when p_score between 0 and 10 then
    30 + (10*p_score) + (case when p_score=10 then 20 else 0 end)
  else 0 end;
$$;

create or replace function public.practice_daily_game_profile()
returns jsonb
language plpgsql stable security definer
set search_path=public,pg_temp
as $$
declare
  v_uid uuid:=auth.uid();
  v_today date:=(now() at time zone 'Africa/Casablanca')::date;
  v_total_xp integer:=0;
  v_count integer:=0;
  v_perfect integer:=0;
  v_month_xp integer:=0;
  v_month_days integer:=0;
  v_best integer:=0;
  v_streak integer:=0;
  v_day date;
  v_level integer:=1;
  v_level_name text:='Découvreur';
  v_floor integer:=0;
  v_next integer:=300;
  v_thresholds integer[]:=array[0,300,800,1600,2800,4500,6500,9000,12500,18000];
  v_names text[]:=array['Découvreur','Explorateur','Régulier','Clinicien','Stratège','Expert','Mentor','Maître des défis','Légende','Élite Practice'];
  v_badges jsonb;
  v_finished_today boolean:=false;
begin
  if v_uid is null or not exists(
    select 1 from public.profiles p
    where p.id=v_uid and p.account_status='active'
  ) then raise exception 'active_account_required';end if;
  select coalesce(sum(public.practice_daily_award_xp(a.score)),0)::integer,
         count(*)::integer,
         count(*) filter(where a.score=10)::integer,
         coalesce(sum(public.practice_daily_award_xp(a.score))
           filter(where a.challenge_date>=date_trunc('month',v_today)::date),0)::integer,
         count(*) filter(where a.challenge_date>=date_trunc('month',v_today)::date)::integer,
         coalesce(bool_or(a.challenge_date=v_today),false)
  into v_total_xp,v_count,v_perfect,v_month_xp,v_month_days,v_finished_today
  from public.practice_daily_attempts a where a.user_id=v_uid;

  select coalesce(max(island_count),0)::integer into v_best
  from (
    select count(*) island_count
    from (
      select a.challenge_date,
        a.challenge_date - row_number() over(order by a.challenge_date)::integer island
      from public.practice_daily_attempts a
      where a.user_id=v_uid
    ) daily
    group by island
  ) islands;

  v_day:=case when v_finished_today then v_today else v_today-1 end;
  loop
    exit when not exists(
      select 1 from public.practice_daily_attempts a
      where a.user_id=v_uid and a.challenge_date=v_day
    );
    v_streak:=v_streak+1;
    v_day:=v_day-1;
  end loop;

  for i in reverse 10..1 loop
    if v_total_xp>=v_thresholds[i] then
      v_level:=i;
      v_level_name:=v_names[i];
      v_floor:=v_thresholds[i];
      v_next:=case when i=10 then v_floor else v_thresholds[i+1] end;
      exit;
    end if;
  end loop;
  v_badges:=jsonb_build_array(
    jsonb_build_object('key','pioneer','title','Premier défi','description','Terminer un défi quotidien','icon','flag','unlocked',v_count>=1),
    jsonb_build_object('key','three_days','title','Régularité','description','Terminer 3 défis','icon','calendar','unlocked',v_count>=3),
    jsonb_build_object('key','week_streak','title','7 jours de suite','description','Atteindre une série de 7 jours','icon','fire','unlocked',v_best>=7),
    jsonb_build_object('key','month_streak','title','30 jours de suite','description','Atteindre une série de 30 jours','icon','fire','unlocked',v_best>=30),
    jsonb_build_object('key','perfect','title','Sans faute','description','Obtenir 10/10 au moins une fois','icon','star','unlocked',v_perfect>=1),
    jsonb_build_object('key','five_perfect','title','Précision clinique','description','Obtenir cinq fois 10/10','icon','target','unlocked',v_perfect>=5),
    jsonb_build_object('key','ten_cases','title','Assidu','description','Terminer 10 défis','icon','medal','unlocked',v_count>=10),
    jsonb_build_object('key','thirty_cases','title','Marathon','description','Terminer 30 défis','icon','trophy','unlocked',v_count>=30)
  );
  return jsonb_build_object(
    'total_xp',v_total_xp,'month_xp',v_month_xp,'days_completed',v_count,
    'month_days',v_month_days,'perfect_days',v_perfect,
    'current_streak',v_streak,'best_streak',v_best,
    'finished_today',v_finished_today,
    'level',v_level,'level_name',v_level_name,
    'level_floor_xp',v_floor,'next_level_xp',v_next,
    'badges',v_badges
  );
end;
$$;

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
  if p_period not in ('month','all') or p_limit is null
     or p_limit<1 or p_limit>100 then raise exception 'invalid_leaderboard_parameters';end if;
  return query
  with scores as (
    select a.user_id,
      sum(public.practice_daily_award_xp(a.score))::bigint total_xp,
      count(*)::bigint days,
      count(*) filter(where a.score=10)::bigint perfect
    from public.practice_daily_attempts a
    where p_period='all' or
      a.challenge_date>=date_trunc('month',v_today)::date
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

revoke all on function public.practice_daily_award_xp(integer) from public,anon;
revoke all on function public.practice_daily_game_profile() from public,anon;
revoke all on function public.practice_daily_game_leaderboard(text,integer) from public,anon;
grant execute on function public.practice_daily_award_xp(integer) to authenticated;
grant execute on function public.practice_daily_game_profile() to authenticated;
grant execute on function public.practice_daily_game_leaderboard(text,integer) to authenticated;
