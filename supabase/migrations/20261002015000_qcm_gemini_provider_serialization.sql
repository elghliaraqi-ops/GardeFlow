-- GardeFlow QCM: avoid provider bursts on Gemini free-tier by allowing only
-- one active QCM generation per user at a time. This is global for old and
-- future clinical cases because it lives in the shared claim RPC.

create or replace function public.clinical_case_claim_qcm_generation(
  p_post_id uuid,
  p_user_id uuid,
  p_force boolean default false
)
returns table(claimed boolean, status text, attempts integer, retry_after timestamptz, error_code text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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

  if v_qcm_count=5 then
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
    ('openai_request_invalid','gemini_request_invalid','gemini_provider_auth_error',
     'authentication_failed','authorization_failed','invalid_request') then
    return query select false,'failed'::text,v_job.attempt_count,null::timestamptz,v_job.last_error_code;
    return;
  end if;

  -- Provider-level serialization. A second case waits instead of hitting
  -- Gemini in parallel. A short recent-start window also closes the race
  -- between two near-simultaneous claims for different posts.
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
$$;

revoke all on function public.clinical_case_claim_qcm_generation(uuid,uuid,boolean)
  from public,anon,authenticated;
grant execute on function public.clinical_case_claim_qcm_generation(uuid,uuid,boolean)
  to service_role;
