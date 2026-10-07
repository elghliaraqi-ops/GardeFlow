-- Practice / QCM improvements deployed 2026-10-07.
-- Keeps immutable first-attempt scoring, allows replay for training,
-- exposes safe edit metadata in feed v2, and invalidates generated QCMs
-- when the owning Practice case is materially edited.

create or replace function public.clinical_case_qcm_summary(p_period text default 'month'::text)
returns table(answered bigint, correct bigint, accuracy numeric)
language plpgsql
stable security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_start timestamptz;
  v_end timestamptz;
begin
  if v_uid is null then raise exception 'Authentification requise.'; end if;
  if p_period not in ('month','year','all') then raise exception 'Période QCM invalide.'; end if;
  if p_period='month' then
    v_start := date_trunc('month',now() at time zone 'Africa/Casablanca') at time zone 'Africa/Casablanca';
    v_end := (date_trunc('month',now() at time zone 'Africa/Casablanca')+interval '1 month') at time zone 'Africa/Casablanca';
  elsif p_period='year' then
    v_start := date_trunc('year',now() at time zone 'Africa/Casablanca') at time zone 'Africa/Casablanca';
    v_end := (date_trunc('year',now() at time zone 'Africa/Casablanca')+interval '1 year') at time zone 'Africa/Casablanca';
  else
    v_start := '-infinity'::timestamptz;
    v_end := 'infinity'::timestamptz;
  end if;

  return query
  with first_attempts as (
    select distinct on (h.user_id,h.qcm_id)
      h.user_id,h.qcm_id,h.is_correct,h.answered_at
    from public.clinical_case_qcm_answer_history h
    order by h.user_id,h.qcm_id,h.answered_at,h.recorded_at,h.answer_id
  )
  select count(*)::bigint,
         count(*) filter(where a.is_correct)::bigint,
         case when count(*)=0 then 0::numeric
              else round(100.0*count(*) filter(where a.is_correct)/count(*),1)
         end
  from first_attempts a
  where a.user_id=v_uid and a.answered_at>=v_start and a.answered_at<v_end;
end;
$function$;

create or replace function public.clinical_case_qcm_leaderboard(
  p_period text default 'month'::text,
  p_promotion smallint default null::smallint
)
returns table(rank bigint,user_id uuid,display_name text,promotion_number smallint,
              correct bigint,answered bigint,accuracy numeric)
language plpgsql
stable security definer
set search_path = ''
as $function$
declare v_start timestamptz; v_end timestamptz;
begin
  if (select auth.uid()) is null then raise exception 'Authentification requise.'; end if;
  if p_period not in ('month','year') then raise exception 'Période QCM invalide.'; end if;
  if p_period='month' then
    v_start:=date_trunc('month',now() at time zone 'Africa/Casablanca') at time zone 'Africa/Casablanca';
    v_end:=(date_trunc('month',now() at time zone 'Africa/Casablanca')+interval '1 month') at time zone 'Africa/Casablanca';
  else
    v_start:=date_trunc('year',now() at time zone 'Africa/Casablanca') at time zone 'Africa/Casablanca';
    v_end:=(date_trunc('year',now() at time zone 'Africa/Casablanca')+interval '1 year') at time zone 'Africa/Casablanca';
  end if;

  return query
  with first_attempts as (
    select distinct on (h.user_id,h.qcm_id)
      h.user_id,h.qcm_id,h.is_correct,h.answered_at
    from public.clinical_case_qcm_answer_history h
    order by h.user_id,h.qcm_id,h.answered_at,h.recorded_at,h.answer_id
  ),
  scores as (
    select p.id uid,
      trim(concat_ws(' ','Dr',nullif(p.prenom,''),nullif(p.nom,''))) display_name,
      p.promotion_number,
      count(*) filter(where a.is_correct)::bigint correct_count,
      count(*)::bigint answered_count,
      round(100.0*count(*) filter(where a.is_correct)/nullif(count(*),0),1) accuracy_pct
    from public.profiles p
    join first_attempts a on a.user_id=p.id
    left join public.practice_preferences pref on pref.user_id=p.id
    where a.answered_at>=v_start and a.answered_at<v_end
      and coalesce(pref.leaderboard_opt_in,true)
      and coalesce(p.account_status,'active')='active'
      and coalesce(p.medical_grade,'junior')='junior'
      and (p_promotion is null or p.promotion_number=p_promotion)
    group by p.id,p.prenom,p.nom,p.promotion_number
  ),
  ranked as (
    select dense_rank() over(
      order by s.correct_count desc,s.accuracy_pct desc,s.answered_count desc,s.uid
    )::bigint rnk,s.*
    from scores s
  )
  select r.rnk,r.uid,r.display_name,r.promotion_number,
         r.correct_count,r.answered_count,r.accuracy_pct
  from ranked r
  order by r.rnk,r.display_name;
end;
$function$;

create or replace function public.clinical_case_reset_my_qcm_answers(p_post_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare v_uid uuid:=auth.uid(); v_count integer:=0;
begin
  if v_uid is null then raise exception 'Authentification requise.'; end if;
  if p_post_id is null then raise exception 'Cas clinique invalide.'; end if;
  if not exists(select 1 from public.clinical_case_posts p where p.id=p_post_id) then
    raise exception 'Cas clinique introuvable.';
  end if;
  delete from public.clinical_case_qcm_answers a
  using public.clinical_case_qcms q
  where a.user_id=v_uid and a.qcm_id=q.id and q.post_id=p_post_id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;
revoke all on function public.clinical_case_reset_my_qcm_answers(uuid) from public, anon;
grant execute on function public.clinical_case_reset_my_qcm_answers(uuid) to authenticated, service_role;

create or replace function public.clinical_case_feed_v2(p_offset integer default 0,p_limit integer default 20)
returns table(
  id uuid,practice_case_id uuid,can_edit boolean,age_band text,sex text,
  presentation text,history text,clinical_exam text,complementary_exams text,
  imaging_conclusion text,assessment text,plan text,disposition text,
  specialist_service text,qcm_question text,qcm_options jsonb,correct_index smallint,
  correction text,question_topic text,generation_source text,published_at timestamptz,
  my_selected_index smallint,my_is_correct boolean,qcms jsonb
)
language plpgsql
stable security definer
set search_path = public, pg_temp
as $function$
declare v_uid uuid:=auth.uid();
begin
  if v_uid is null then raise exception 'Clinical cases: authentification requise.'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_uid and p.account_status='active') then
    raise exception 'Clinical cases: compte non actif.';
  end if;
  return query
  select c.id,c.practice_case_id,(c.author_id=v_uid),c.age_band,c.sex,c.presentation,
    c.history,c.clinical_exam,c.complementary_exams,c.imaging_conclusion,c.assessment,
    c.plan,c.disposition,c.specialist_service,
    case when c.generation_source='openai' then c.qcm_question else '' end,
    case when c.generation_source='openai' then c.qcm_options else '[]'::jsonb end,
    case when c.generation_source='openai' and legacy.post_id is not null then c.correct_index else null::smallint end,
    case when c.generation_source='openai' and legacy.post_id is not null then c.correction else '' end,
    case when c.generation_source='openai' then c.question_topic else '' end,
    c.generation_source,c.published_at,legacy.selected_index,legacy.is_correct,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',q.id,'position',q.position,'question',q.question,'options',q.options,
        'correct_index',case when ans.id is null then null else q.correct_index end,
        'correction',case when ans.id is null then '' else q.correction end,
        'topic',q.topic,'generation_source',q.generation_source,
        'my_selected_index',ans.selected_index,'my_is_correct',ans.is_correct,
        'answered_at',ans.answered_at
      ) order by q.position)
      from public.clinical_case_qcms q
      left join public.clinical_case_qcm_answers ans
        on ans.qcm_id=q.id and ans.user_id=v_uid
      where q.post_id=c.id and q.generation_source='openai'
    ),'[]'::jsonb)
  from public.clinical_case_posts c
  left join public.clinical_case_qcm_attempts legacy
    on legacy.post_id=c.id and legacy.user_id=v_uid
  order by c.published_at desc,c.id desc
  offset greatest(coalesce(p_offset,0),0)
  limit least(greatest(coalesce(p_limit,20),1),100);
end;
$function$;
revoke all on function public.clinical_case_feed_v2(integer,integer) from public, anon;
grant execute on function public.clinical_case_feed_v2(integer,integer) to authenticated, service_role;

create or replace function public.clinical_case_invalidate_qcms_after_edit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare v_post uuid;
begin
  if new.is_draft or old.is_draft or row(
    new.age,new.sex,new.chief_complaint,new.interrogatoire,new.personal_surgical_history,
    new.personal_medical_history,new.family_surgical_history,new.family_medical_history,
    new.consultation_reason,new.illness_history,new.clinical_exam,new.complementary_exams,
    new.imaging_conclusion,new.assessment,new.plan,new.specialist_opinion_requested,
    new.specialist_service,new.specialist_opinion_done,new.waiting,new.prescription_done,
    new.discharged,new.hospitalized,new.hospitalization_service
  ) is not distinct from row(
    old.age,old.sex,old.chief_complaint,old.interrogatoire,old.personal_surgical_history,
    old.personal_medical_history,old.family_surgical_history,old.family_medical_history,
    old.consultation_reason,old.illness_history,old.clinical_exam,old.complementary_exams,
    old.imaging_conclusion,old.assessment,old.plan,old.specialist_opinion_requested,
    old.specialist_service,old.specialist_opinion_done,old.waiting,old.prescription_done,
    old.discharged,old.hospitalized,old.hospitalization_service
  ) then return new; end if;

  select p.id into v_post from public.clinical_case_posts p where p.practice_case_id=new.id;
  if v_post is null then return new; end if;

  delete from public.clinical_case_qcm_answers a
  using public.clinical_case_qcms q
  where a.qcm_id=q.id and q.post_id=v_post;

  update public.clinical_case_qcms
  set generation_source='fallback',ai_provider=null,updated_at=now()
  where post_id=v_post;

  update public.clinical_case_posts
  set qcm_generation_status='idle',qcm_generation_attempts=0,
      qcm_generation_started_at=null,qcm_generation_finished_at=null,
      qcm_generation_last_error=null,qcm_generation_retry_after=null,
      qcm_ai_provider=null,updated_at=now()
  where id=v_post;

  update public.clinical_case_qcm_generation_jobs
  set status='pending',attempt_count=0,started_at=null,finished_at=null,
      last_error_code=null,retry_after=null,updated_at=now()
  where post_id=v_post;
  return new;
end;
$function$;

drop trigger if exists zz_clinical_case_invalidate_qcms_after_edit on public.practice_cases;
create trigger zz_clinical_case_invalidate_qcms_after_edit
after update on public.practice_cases
for each row execute function public.clinical_case_invalidate_qcms_after_edit();

revoke all on function public.clinical_case_invalidate_qcms_after_edit() from public, anon, authenticated;
grant execute on function public.clinical_case_invalidate_qcms_after_edit() to service_role;
