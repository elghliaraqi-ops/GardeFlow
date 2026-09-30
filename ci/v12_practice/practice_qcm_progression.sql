-- Practice progression now combines clinical documentation and QCM learning.
-- Clinical XP stays unchanged: 10 XP per valid case + 2 XP for a complete case.
-- QCM XP is deliberately lighter: 2 XP per answered QCM + 3 XP bonus when correct.
-- Guard-scoped clinical statistics remain clinical-only; month/year/all XP and
-- the overall Practice leaderboard include both activities.

create or replace function public.practice_summary(
  p_scope text default 'month'::text,
  p_guard_id text default null::text
)
returns table(
  patients bigint,
  waiting bigint,
  discharged bigint,
  hospitalized bigint,
  specialist_opinions bigint,
  prescriptions bigint,
  complete_observations bigint,
  guards_count bigint,
  average_per_guard numeric,
  best_guard bigint,
  xp bigint,
  streak integer
)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  uid uuid := auth.uid();
  start_date date;
  end_date date;
  local_today date := (now() at time zone 'Africa/Casablanca')::date;
  qcm_xp bigint := 0;
begin
  if uid is null then raise exception 'Authentification requise.'; end if;
  if p_scope not in ('guard','month','year','all') then raise exception 'Scope Practice invalide.'; end if;
  if p_scope='guard' and p_guard_id is null then raise exception 'guard_id requis.'; end if;

  if p_scope='month' then
    start_date := date_trunc('month', local_today)::date;
    end_date := (date_trunc('month', local_today) + interval '1 month')::date;
  elsif p_scope='year' then
    start_date := date_trunc('year', local_today)::date;
    end_date := (date_trunc('year', local_today) + interval '1 year')::date;
  end if;

  if p_scope <> 'guard' then
    select coalesce(
      count(*) * 2 + count(*) filter(where a.is_correct) * 3,
      0
    )::bigint
    into qcm_xp
    from public.clinical_case_qcm_attempts a
    where a.user_id = uid
      and (
        p_scope not in ('month','year')
        or (
          (a.answered_at at time zone 'Africa/Casablanca')::date >= start_date
          and (a.answered_at at time zone 'Africa/Casablanca')::date < end_date
        )
      );
  end if;

  return query
  with base as (
    select pc.*
    from public.practice_cases pc
    where pc.user_id = uid
      and pc.is_draft = false
      and public.practice_case_is_valid(pc)
      and (p_scope <> 'guard' or pc.guard_id = p_guard_id)
      and (
        p_scope not in ('month','year')
        or (pc.guard_date >= start_date and pc.guard_date < end_date)
      )
  ),
  per_guard as (
    select guard_id, count(*)::bigint n
    from base
    group by guard_id
  )
  select
    count(*)::bigint,
    count(*) filter(where b.waiting)::bigint,
    count(*) filter(where b.discharged)::bigint,
    count(*) filter(where b.hospitalized)::bigint,
    count(*) filter(where b.specialist_opinion_requested)::bigint,
    count(*) filter(where b.prescription_done)::bigint,
    count(*) filter(where public.practice_case_is_complete(b))::bigint,
    (select count(*)::bigint from per_guard),
    coalesce((select round(avg(n)::numeric,1) from per_guard),0),
    coalesce((select max(n) from per_guard),0)::bigint,
    coalesce(sum(public.practice_case_xp(b)),0)::bigint + qcm_xp,
    public.practice_current_streak(uid)
  from base b;
end;
$function$;

create or replace function public.practice_leaderboard(
  p_period text default 'month'::text,
  p_promotion smallint default null::smallint
)
returns table(
  rank bigint,
  user_id uuid,
  display_name text,
  promotion_number smallint,
  hospital text,
  xp bigint,
  case_count bigint
)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  start_date date;
  end_date date;
  local_today date := (now() at time zone 'Africa/Casablanca')::date;
begin
  if auth.uid() is null then raise exception 'Authentification requise.'; end if;
  if p_period not in ('month','year') then raise exception 'Période Practice invalide.'; end if;

  if p_period='month' then
    start_date := date_trunc('month',local_today)::date;
    end_date := (date_trunc('month',local_today)+interval '1 month')::date;
  else
    start_date := date_trunc('year',local_today)::date;
    end_date := (date_trunc('year',local_today)+interval '1 year')::date;
  end if;

  return query
  with clinical as (
    select
      pc.user_id,
      coalesce(sum(public.practice_case_xp(pc)),0)::bigint clinical_xp,
      count(pc.id)::bigint cases
    from public.practice_cases pc
    where pc.is_draft = false
      and public.practice_case_is_valid(pc)
      and pc.guard_date >= start_date
      and pc.guard_date < end_date
    group by pc.user_id
  ),
  qcm as (
    select
      a.user_id,
      (count(*) * 2 + count(*) filter(where a.is_correct) * 3)::bigint qcm_xp,
      count(*)::bigint qcms
    from public.clinical_case_qcm_attempts a
    where (a.answered_at at time zone 'Africa/Casablanca')::date >= start_date
      and (a.answered_at at time zone 'Africa/Casablanca')::date < end_date
    group by a.user_id
  ),
  scores as (
    select
      p.id uid,
      trim(concat_ws(' ','Dr',nullif(p.prenom,''),nullif(p.nom,''))) display_name,
      p.promotion_number,
      p.hospital,
      (coalesce(c.clinical_xp,0) + coalesce(q.qcm_xp,0))::bigint score,
      coalesce(c.cases,0)::bigint cases,
      coalesce(q.qcms,0)::bigint qcms
    from public.profiles p
    left join public.practice_preferences pref on pref.user_id = p.id
    left join clinical c on c.user_id = p.id
    left join qcm q on q.user_id = p.id
    where coalesce(pref.leaderboard_opt_in,true)
      and coalesce(p.account_status,'active')='active'
      and coalesce(p.medical_grade,'junior')='junior'
      and (p_promotion is null or p.promotion_number=p_promotion)
      and (coalesce(c.cases,0) > 0 or coalesce(q.qcms,0) > 0)
  )
  select
    dense_rank() over(order by s.score desc, s.cases desc, s.qcms desc, s.uid)::bigint,
    s.uid,
    s.display_name,
    s.promotion_number,
    s.hospital,
    s.score,
    s.cases
  from scores s
  order by 1, s.display_name;
end;
$function$;

insert into public.practice_achievements(key,name,description,metric,threshold,icon,sort_order)
values
  ('qcm_first','Premier QCM','Répondre à votre premier QCM issu d’un cas clinique.','qcm_answered',1,'quiz',140),
  ('qcm_10','10 QCM répondus','Répondre à 10 QCM Practice.','qcm_answered',10,'quiz',150),
  ('qcm_25','25 QCM répondus','Répondre à 25 QCM Practice.','qcm_answered',25,'quiz',160),
  ('qcm_50','50 QCM répondus','Répondre à 50 QCM Practice.','qcm_answered',50,'school',170),
  ('qcm_100','100 QCM répondus','Répondre à 100 QCM Practice.','qcm_answered',100,'school',180),
  ('qcm_correct_10','10 QCM réussis','Obtenir 10 réponses correctes aux QCM Practice.','qcm_correct',10,'check_circle',190),
  ('qcm_correct_25','25 QCM réussis','Obtenir 25 réponses correctes aux QCM Practice.','qcm_correct',25,'check_circle',200),
  ('qcm_correct_50','50 QCM réussis','Obtenir 50 réponses correctes aux QCM Practice.','qcm_correct',50,'verified',210),
  ('qcm_correct_100','100 QCM réussis','Obtenir 100 réponses correctes aux QCM Practice.','qcm_correct',100,'verified',220),
  ('practice_xp_500','500 XP Practice','Atteindre 500 XP en combinant cas documentés et QCM.','xp',500,'trending_up',230),
  ('practice_xp_1000','1 000 XP Practice','Atteindre 1 000 XP en combinant cas documentés et QCM.','xp',1000,'trending_up',240),
  ('practice_xp_2500','2 500 XP Practice','Atteindre 2 500 XP en combinant cas documentés et QCM.','xp',2500,'workspace_premium',250)
on conflict(key) do update set
  name=excluded.name,
  description=excluded.description,
  metric=excluded.metric,
  threshold=excluded.threshold,
  icon=excluded.icon,
  sort_order=excluded.sort_order;

create or replace function public.practice_refresh_my_achievements()
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  uid uuid := auth.uid();
  a record;
  progress_value integer;
  total_patients integer;
  total_complete integer;
  total_specialist integer;
  total_guards integer;
  current_streak integer;
  qcm_answered integer;
  qcm_correct integer;
  clinical_xp integer;
  combined_xp integer;
begin
  if uid is null then raise exception 'Authentification requise.'; end if;

  select
    count(*)::int,
    count(*) filter(where public.practice_case_is_complete(pc))::int,
    count(*) filter(where pc.specialist_opinion_requested)::int,
    count(distinct pc.guard_id)::int,
    coalesce(sum(public.practice_case_xp(pc)),0)::int
  into total_patients,total_complete,total_specialist,total_guards,clinical_xp
  from public.practice_cases pc
  where pc.user_id=uid
    and pc.is_draft=false
    and public.practice_case_is_valid(pc);

  select
    count(*)::int,
    count(*) filter(where qa.is_correct)::int
  into qcm_answered,qcm_correct
  from public.clinical_case_qcm_attempts qa
  where qa.user_id=uid;

  current_streak := public.practice_current_streak(uid);
  combined_xp := clinical_xp + qcm_answered * 2 + qcm_correct * 3;

  for a in select * from public.practice_achievements loop
    progress_value := case a.metric
      when 'patients' then total_patients
      when 'complete' then total_complete
      when 'specialist' then total_specialist
      when 'guards' then total_guards
      when 'streak' then current_streak
      when 'qcm_answered' then qcm_answered
      when 'qcm_correct' then qcm_correct
      when 'xp' then combined_xp
      else 0
    end;

    insert into public.user_practice_achievements(
      user_id,achievement_id,progress,unlocked_at,updated_at
    )
    values(
      uid,
      a.id,
      progress_value,
      case when progress_value>=a.threshold then now() else null end,
      now()
    )
    on conflict(user_id,achievement_id) do update set
      progress=excluded.progress,
      unlocked_at=coalesce(public.user_practice_achievements.unlocked_at,excluded.unlocked_at),
      updated_at=now();
  end loop;
end;
$function$;
