-- Enable authenticated owner/admin forced re-generation of ready cases.
CREATE OR REPLACE FUNCTION public.clinical_case_claim_qcm_generation(p_post_id uuid, p_user_id uuid, p_force boolean DEFAULT false)
 RETURNS TABLE(claimed boolean, status text, attempts integer, retry_after timestamp with time zone, error_code text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_post public.clinical_case_posts%rowtype;
  v_job public.clinical_case_qcm_generation_jobs%rowtype;
  v_qcm_count integer := 0;
  v_busy_count integer := 0;
  v_day_count integer := 0;
  v_attempts integer := 0;
  v_retry timestamptz;
begin
  if p_post_id is null or p_user_id is null then
    return query select false,'failed'::text,0,null::timestamptz,'invalid_request'::text;
    return;
  end if;

  select * into v_post
  from public.clinical_case_posts
  where id=p_post_id
  for update;

  if not found then
    return query select false,'failed'::text,0,null::timestamptz,'case_not_found'::text;
    return;
  end if;

  select count(*)::integer into v_qcm_count
  from public.clinical_case_qcms q
  where q.post_id=p_post_id and q.generation_source='openai';

  insert into public.clinical_case_qcm_generation_jobs(post_id,requested_by,status)
  values(p_post_id,p_user_id,case when v_qcm_count=5 then 'ready' else 'pending' end)
  on conflict(post_id) do nothing;

  select * into v_job
  from public.clinical_case_qcm_generation_jobs
  where post_id=p_post_id
  for update;

  if v_qcm_count=5 and not p_force then
    update public.clinical_case_qcm_generation_jobs
      set status='ready',finished_at=coalesce(finished_at,now()),last_error_code=null,
          retry_after=null,updated_at=now()
      where post_id=p_post_id;
    update public.clinical_case_posts
      set qcm_generation_status='ready',
          qcm_generation_finished_at=coalesce(qcm_generation_finished_at,now()),
          qcm_generation_last_error=null,qcm_generation_retry_after=null
      where id=p_post_id;
    return query select false,'ready'::text,v_job.attempt_count,null::timestamptz,null::text;
    return;
  end if;

  if v_job.status='running' and v_job.started_at > now()-interval '2 minutes' then
    return query select false,'running'::text,v_job.attempt_count,
      v_job.started_at+interval '2 minutes','generation_in_progress'::text;
    return;
  end if;

  if not p_force and v_job.retry_after is not null and v_job.retry_after>now() then
    return query select false,'failed'::text,v_job.attempt_count,v_job.retry_after,
      coalesce(v_job.last_error_code,'retry_later');
    return;
  end if;

  if not p_force and v_job.last_error_code in
    ('openai_request_invalid','groq_request_invalid','gemini_request_invalid','gemini_provider_auth_error',
     'authentication_failed','authorization_failed','invalid_request') then
    return query select false,'failed'::text,v_job.attempt_count,null::timestamptz,v_job.last_error_code;
    return;
  end if;

  select count(*)::integer into v_busy_count
  from public.clinical_case_qcm_generation_jobs j
  where j.requested_by=p_user_id
    and j.post_id<>p_post_id
    and j.started_at is not null
    and (
      (j.status='running' and j.started_at>now()-interval '2 minutes')
      or j.started_at>now()-interval '30 seconds'
    );

  if v_busy_count>=1 then
    v_retry:=now()+interval '45 seconds';
    return query select false,'running'::text,v_job.attempt_count,v_retry,'provider_queue_busy'::text;
    return;
  end if;

  select count(*)::integer into v_day_count
  from public.clinical_case_qcm_generation_jobs j
  where j.requested_by=p_user_id and j.post_id<>p_post_id
    and j.started_at>=date_trunc('day',now());
  if v_day_count>=30 then
    v_retry:=date_trunc('day',now())+interval '1 day';
    return query select false,'failed'::text,v_job.attempt_count,v_retry,'rate_limit_exceeded'::text;
    return;
  end if;

  v_attempts:=case
    when v_job.started_at is null or v_job.started_at<=now()-interval '24 hours' then 1
    else least(v_job.attempt_count+1,100)
  end;

  update public.clinical_case_qcm_generation_jobs
  set requested_by=p_user_id,status='running',started_at=now(),finished_at=null,
      attempt_count=v_attempts,last_error_code=null,retry_after=null,updated_at=now()
  where post_id=p_post_id;

  update public.clinical_case_posts
  set qcm_generation_status='running',qcm_generation_attempts=v_attempts,
      qcm_generation_started_at=now(),qcm_generation_finished_at=null,
      qcm_generation_last_error=null,qcm_generation_retry_after=null
  where id=p_post_id;

  return query select true,'running'::text,v_attempts,null::timestamptz,null::text;
end;
$function$


-- Private before-image of clinical-case QCM repair and existing answers.
create schema if not exists private;
create table if not exists private.clinical_case_qcm_repair_archive (
  id bigint generated always as identity primary key,
  case_post_id uuid not null,
  archived_at timestamptz not null default now(),
  reason text not null,
  qcms jsonb not null,
  answers jsonb not null,
  answer_history jsonb not null,
  legacy_attempts jsonb not null
);
revoke all on private.clinical_case_qcm_repair_archive from public, anon, authenticated;
