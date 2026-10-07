alter table public.practice_cases
  add column if not exists encounter_context text not null default 'emergency_guard';

alter table public.practice_cases
  alter column guard_id drop not null,
  alter column guard_shift_id drop not null;

alter table public.practice_cases
  drop constraint if exists practice_cases_shift_emergency;

alter table public.practice_cases
  drop constraint if exists practice_cases_encounter_context_check;

alter table public.practice_cases
  add constraint practice_cases_encounter_context_check
  check (
    (encounter_context='emergency_guard'
      and guard_id is not null
      and guard_shift_id in ('urg-jour','urg-nuit','urg-24h'))
    or
    (encounter_context='standalone'
      and guard_id is null
      and guard_shift_id is null)
  );

create index if not exists idx_practice_cases_standalone_user_date
  on public.practice_cases(user_id,guard_date desc)
  where encounter_context='standalone';

create or replace function public.practice_before_case_write()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare g record;
begin
  new.encounter_context:=coalesce(nullif(new.encounter_context,''),'emergency_guard');

  if new.encounter_context='standalone' then
    new.guard_id:=null;
    new.guard_shift_id:=null;
    new.guard_date:=coalesce(new.guard_date,(now() at time zone 'Africa/Casablanca')::date);

    if tg_op='INSERT' then
      perform pg_advisory_xact_lock(
        hashtext(new.user_id::text || ':standalone:' || new.guard_date::text)
      );
      select coalesce(max(patient_number),0)+1
      into new.patient_number
      from public.practice_cases
      where user_id=new.user_id
        and encounter_context='standalone'
        and guard_date=new.guard_date;
    elsif new.patient_number is null or new.patient_number<=0 then
      new.patient_number:=old.patient_number;
    end if;
  else
    new.encounter_context:='emergency_guard';

    if tg_op='INSERT'
       or new.guard_id is distinct from old.guard_id
       or new.user_id is distinct from old.user_id
       or new.encounter_context is distinct from old.encounter_context then
      select id,date_str,shift_id,owner_id
      into g
      from public.planning_entries
      where id=new.guard_id and deleted_at is null
      limit 1;

      if g.id is null then raise exception 'Practice: garde introuvable ou supprimée.'; end if;
      if g.owner_id<>new.user_id then raise exception 'Practice: cette garde n’appartient pas à cet utilisateur.'; end if;
      if g.shift_id not in ('urg-jour','urg-nuit','urg-24h') then
        raise exception 'Practice: seules les gardes Urgences sont acceptées.';
      end if;
      new.guard_date:=g.date_str;
      new.guard_shift_id:=g.shift_id;
    end if;

    if new.patient_number is null or new.patient_number<=0 then
      perform pg_advisory_xact_lock(hashtext(new.user_id::text || ':' || new.guard_id));
      select coalesce(max(patient_number),0)+1
      into new.patient_number
      from public.practice_cases
      where user_id=new.user_id and guard_id=new.guard_id;
    end if;
  end if;

  if new.specialist_opinion_requested is false then
    new.specialist_service:=null;
    new.specialist_opinion_done:=false;
  end if;
  if new.hospitalized is false then new.hospitalization_service:=null; end if;
  if new.is_draft is false and not public.practice_case_is_valid(new) then
    raise exception 'Practice: motif + au moins une section clinique sont requis.';
  end if;

  new.updated_at:=now();
  if new.is_draft is false then new.synced_at:=coalesce(new.synced_at,now()); end if;
  return new;
end;
$function$;

create or replace function public.practice_monthly_counts(p_year integer default null::integer)
returns table(month integer, patients bigint)
language sql
stable security definer
set search_path to 'public'
as $function$
  with months as(select generate_series(1,12) m),
  uid as(select auth.uid() u),
  target as(
    select coalesce(
      p_year,
      extract(year from (now() at time zone 'Africa/Casablanca'))::int
    ) y
  )
  select months.m,count(pc.id)::bigint
  from months cross join uid cross join target
  left join public.practice_cases pc
    on pc.user_id=uid.u
   and pc.encounter_context='emergency_guard'
   and pc.is_draft=false
   and public.practice_case_is_valid(pc)
   and extract(year from pc.guard_date)::int=target.y
   and extract(month from pc.guard_date)::int=months.m
  group by months.m
  order by months.m;
$function$;

create or replace function public.practice_summary(
  p_scope text default 'month'::text,
  p_guard_id text default null::text
)
returns table(
  patients bigint,waiting bigint,discharged bigint,hospitalized bigint,
  specialist_opinions bigint,prescriptions bigint,complete_observations bigint,
  guards_count bigint,average_per_guard numeric,best_guard bigint,xp bigint,streak integer
)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  uid uuid:=auth.uid();
  start_date date;
  end_date date;
  local_today date:=(now() at time zone 'Africa/Casablanca')::date;
  qcm_xp bigint:=0;
begin
  if uid is null then raise exception 'Authentification requise.'; end if;
  if p_scope not in ('guard','month','year','all') then raise exception 'Scope Practice invalide.'; end if;
  if p_scope='guard' and p_guard_id is null then raise exception 'guard_id requis.'; end if;

  if p_scope='month' then
    start_date:=date_trunc('month',local_today)::date;
    end_date:=(date_trunc('month',local_today)+interval '1 month')::date;
  elsif p_scope='year' then
    start_date:=date_trunc('year',local_today)::date;
    end_date:=(date_trunc('year',local_today)+interval '1 year')::date;
  end if;

  if p_scope<>'guard' then
    select coalesce(count(*)*2+count(*) filter(where a.is_correct)*3,0)::bigint
    into qcm_xp
    from public.clinical_case_qcm_answer_history a
    where a.user_id=uid
      and (
        p_scope not in ('month','year')
        or (
          (a.answered_at at time zone 'Africa/Casablanca')::date>=start_date
          and (a.answered_at at time zone 'Africa/Casablanca')::date<end_date
        )
      );
  end if;

  return query
  with base as(
    select pc.*
    from public.practice_cases pc
    where pc.user_id=uid
      and pc.encounter_context='emergency_guard'
      and pc.is_draft=false
      and public.practice_case_is_valid(pc)
      and (p_scope<>'guard' or pc.guard_id=p_guard_id)
      and (
        p_scope not in ('month','year')
        or (pc.guard_date>=start_date and pc.guard_date<end_date)
      )
  ),
  per_guard as(
    select guard_id,count(*)::bigint n from base group by guard_id
  )
  select count(*)::bigint,
    count(*) filter(where b.waiting)::bigint,
    count(*) filter(where b.discharged)::bigint,
    count(*) filter(where b.hospitalized)::bigint,
    count(*) filter(where b.specialist_opinion_requested)::bigint,
    count(*) filter(where b.prescription_done)::bigint,
    count(*) filter(where public.practice_case_is_complete(b))::bigint,
    (select count(*)::bigint from per_guard),
    coalesce((select round(avg(n)::numeric,1) from per_guard),0),
    coalesce((select max(n) from per_guard),0)::bigint,
    coalesce(sum(public.practice_case_xp(b)),0)::bigint+qcm_xp,
    public.practice_current_streak(uid)
  from base b;
end;
$function$;

create or replace function public.practice_leaderboard(
  p_period text default 'month'::text,
  p_promotion smallint default null::smallint
)
returns table(
  rank bigint,user_id uuid,display_name text,promotion_number smallint,
  hospital text,xp bigint,case_count bigint
)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  start_date date;
  end_date date;
  local_today date:=(now() at time zone 'Africa/Casablanca')::date;
begin
  if auth.uid() is null then raise exception 'Authentification requise.'; end if;
  if p_period not in ('month','year') then raise exception 'Période Practice invalide.'; end if;
  if p_period='month' then
    start_date:=date_trunc('month',local_today)::date;
    end_date:=(date_trunc('month',local_today)+interval '1 month')::date;
  else
    start_date:=date_trunc('year',local_today)::date;
    end_date:=(date_trunc('year',local_today)+interval '1 year')::date;
  end if;

  return query
  with clinical as(
    select pc.user_id,
      coalesce(sum(public.practice_case_xp(pc)),0)::bigint clinical_xp,
      count(pc.id)::bigint cases
    from public.practice_cases pc
    where pc.encounter_context='emergency_guard'
      and pc.is_draft=false
      and public.practice_case_is_valid(pc)
      and pc.guard_date>=start_date
      and pc.guard_date<end_date
    group by pc.user_id
  ),
  qcm as(
    select a.user_id,
      (count(*)*2+count(*) filter(where a.is_correct)*3)::bigint qcm_xp,
      count(*)::bigint qcms
    from public.clinical_case_qcm_answer_history a
    where (a.answered_at at time zone 'Africa/Casablanca')::date>=start_date
      and (a.answered_at at time zone 'Africa/Casablanca')::date<end_date
    group by a.user_id
  ),
  scores as(
    select p.id uid,
      trim(concat_ws(' ','Dr',nullif(p.prenom,''),nullif(p.nom,''))) display_name,
      p.promotion_number,p.hospital,
      (coalesce(c.clinical_xp,0)+coalesce(q.qcm_xp,0))::bigint score,
      coalesce(c.cases,0)::bigint cases,
      coalesce(q.qcms,0)::bigint qcms
    from public.profiles p
    left join public.practice_preferences pref on pref.user_id=p.id
    left join clinical c on c.user_id=p.id
    left join qcm q on q.user_id=p.id
    where coalesce(pref.leaderboard_opt_in,true)
      and coalesce(p.account_status,'active')='active'
      and coalesce(p.medical_grade,'junior')='junior'
      and (p_promotion is null or p.promotion_number=p_promotion)
      and (coalesce(c.cases,0)>0 or coalesce(q.qcms,0)>0)
  )
  select dense_rank() over(
      order by s.score desc,s.cases desc,s.qcms desc,s.uid
    )::bigint,
    s.uid,s.display_name,s.promotion_number,s.hospital,s.score,s.cases
  from scores s
  order by 1,s.display_name;
end;
$function$;

create or replace function public.practice_refresh_my_achievements()
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  uid uuid:=(select auth.uid());
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

  select count(*)::int,
    count(*) filter(where public.practice_case_is_complete(pc))::int,
    count(*) filter(where pc.specialist_opinion_requested)::int,
    count(distinct pc.guard_id)::int,
    coalesce(sum(public.practice_case_xp(pc)),0)::int
  into total_patients,total_complete,total_specialist,total_guards,clinical_xp
  from public.practice_cases pc
  where pc.user_id=uid
    and pc.encounter_context='emergency_guard'
    and pc.is_draft=false
    and public.practice_case_is_valid(pc);

  select count(*)::int,count(*) filter(where qa.is_correct)::int
  into qcm_answered,qcm_correct
  from private.clinical_case_qcm_response_events qa
  where qa.stats_user_id=uid;

  current_streak:=public.practice_current_streak(uid);
  combined_xp:=clinical_xp+qcm_answered*2+qcm_correct*3;

  for a in select * from public.practice_achievements loop
    progress_value:=case a.metric
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
      uid,a.id,progress_value,
      case when progress_value>=a.threshold then now() else null end,
      now()
    )
    on conflict(user_id,achievement_id) do update
    set progress=excluded.progress,
      unlocked_at=coalesce(public.user_practice_achievements.unlocked_at,excluded.unlocked_at),
      updated_at=now();
  end loop;
end;
$function$;
