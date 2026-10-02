-- GardeFlow QCM: Groq is the only AI provider. Keep generation_source='openai'
-- temporarily as a legacy client-compatibility marker; ai_provider is authoritative.

comment on column public.clinical_case_qcms.ai_provider is
  'Actual AI provider used for this QCM. Current production provider: groq. generation_source remains a legacy compatibility marker.';
comment on column public.clinical_case_posts.qcm_ai_provider is
  'Actual AI provider used for the current generated QCM set. Current production provider: groq.';

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

  select * into v_post from public.clinical_case_posts where id=p_post_id for update;
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

  select * into v_job from public.clinical_case_qcm_generation_jobs where post_id=p_post_id for update;

  if v_qcm_count=5 then
    update public.clinical_case_qcm_generation_jobs
      set status='ready',finished_at=coalesce(finished_at,now()),last_error_code=null,retry_after=null,updated_at=now()
      where post_id=p_post_id;
    update public.clinical_case_posts
      set qcm_generation_status='ready',qcm_generation_finished_at=coalesce(qcm_generation_finished_at,now()),qcm_generation_last_error=null,qcm_generation_retry_after=null
      where id=p_post_id;
    return query select false,'ready'::text,v_job.attempt_count,null::timestamptz,null::text;
    return;
  end if;

  if v_job.status='running' and v_job.started_at > now()-interval '2 minutes' then
    return query select false,'running'::text,v_job.attempt_count,v_job.started_at+interval '2 minutes','generation_in_progress'::text;
    return;
  end if;

  if not p_force and v_job.retry_after is not null and v_job.retry_after>now() then
    return query select false,'failed'::text,v_job.attempt_count,v_job.retry_after,coalesce(v_job.last_error_code,'retry_later');
    return;
  end if;

  if not p_force and v_job.last_error_code in
    ('groq_request_invalid','groq_provider_auth_error','groq_model_not_found',
     'authentication_failed','authorization_failed','invalid_request') then
    return query select false,'failed'::text,v_job.attempt_count,null::timestamptz,v_job.last_error_code;
    return;
  end if;

  select count(*)::integer into v_busy_count
  from public.clinical_case_qcm_generation_jobs j
  where j.requested_by=p_user_id
    and j.post_id<>p_post_id
    and j.started_at is not null
    and ((j.status='running' and j.started_at>now()-interval '2 minutes') or j.started_at>now()-interval '30 seconds');

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
    set requested_by=p_user_id,status='running',started_at=now(),finished_at=null,attempt_count=v_attempts,last_error_code=null,retry_after=null,updated_at=now()
    where post_id=p_post_id;
  update public.clinical_case_posts
    set qcm_generation_status='running',qcm_generation_attempts=v_attempts,qcm_generation_started_at=now(),qcm_generation_finished_at=null,qcm_generation_last_error=null,qcm_generation_retry_after=null
    where id=p_post_id;

  return query select true,'running'::text,v_attempts,null::timestamptz,null::text;
end;
$$;

create or replace function public.clinical_case_finish_qcm_generation(
  p_post_id uuid,
  p_success boolean,
  p_error_code text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_attempts integer := 1;
  v_retry timestamptz;
  v_code text := left(regexp_replace(coalesce(p_error_code,'generation_failed'),'[^a-zA-Z0-9_:-]','','g'),80);
begin
  if v_code='' then v_code:='generation_failed'; end if;
  select greatest(attempt_count,1) into v_attempts from public.clinical_case_qcm_generation_jobs where post_id=p_post_id for update;
  if not found then
    select greatest(qcm_generation_attempts,1) into v_attempts from public.clinical_case_posts where id=p_post_id for update;
    if not found then return; end if;
  end if;

  if p_success then
    update public.clinical_case_qcm_generation_jobs set status='ready',finished_at=now(),last_error_code=null,retry_after=null,updated_at=now() where post_id=p_post_id;
    update public.clinical_case_posts set qcm_generation_status='ready',qcm_generation_finished_at=now(),qcm_generation_last_error=null,qcm_generation_retry_after=null where id=p_post_id;
    return;
  end if;

  v_retry:=now()+case when v_attempts<=1 then interval '1 minute' when v_attempts=2 then interval '5 minutes' when v_attempts=3 then interval '15 minutes' else interval '1 hour' end;
  if v_code in ('groq_request_invalid','groq_provider_auth_error','groq_model_not_found','authentication_failed','authorization_failed','invalid_request') then
    v_retry:=null;
  end if;

  update public.clinical_case_qcm_generation_jobs set status='failed',finished_at=now(),last_error_code=v_code,retry_after=v_retry,updated_at=now() where post_id=p_post_id;
  update public.clinical_case_posts set qcm_generation_status='failed',qcm_generation_finished_at=now(),qcm_generation_last_error=v_code,qcm_generation_retry_after=v_retry where id=p_post_id;
end;
$$;

create or replace function public.clinical_case_commit_generated_qcms(p_post_id uuid,p_qcms jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_item jsonb;
  v_first jsonb;
  v_positions integer[] := '{}';
begin
  if p_post_id is null or jsonb_typeof(p_qcms)<>'array' or jsonb_array_length(p_qcms)<>5 then
    raise exception 'invalid_qcm_payload';
  end if;

  for v_item in select value from jsonb_array_elements(p_qcms)
  loop
    if coalesce(length(trim(v_item->>'question')),0)=0
      or coalesce(length(trim(v_item->>'correction')),0)=0
      or jsonb_typeof(v_item->'options')<>'array'
      or jsonb_array_length(v_item->'options')<>4
      or (v_item->>'correct_index')::integer not between 0 and 3
      or (v_item->>'position')::integer not between 1 and 5
      or position('§SOURCES§' in (v_item->>'correction'))=0 then
      raise exception 'invalid_qcm_payload';
    end if;
    v_positions:=array_append(v_positions,(v_item->>'position')::integer);
  end loop;

  if (select count(distinct x) from unnest(v_positions) x)<>5 then raise exception 'invalid_qcm_positions'; end if;
  select value into v_first from jsonb_array_elements(p_qcms) where (value->>'position')::integer=1 limit 1;

  insert into public.clinical_case_qcms(post_id,position,question,options,correct_index,correction,topic,generation_source,ai_provider,updated_at)
  select p_post_id,(x->>'position')::smallint,trim(x->>'question'),x->'options',(x->>'correct_index')::smallint,x->>'correction',trim(x->>'topic'),'openai','groq',now()
  from jsonb_array_elements(p_qcms) x
  on conflict(post_id,position) do update set
    question=excluded.question,options=excluded.options,correct_index=excluded.correct_index,correction=excluded.correction,topic=excluded.topic,generation_source='openai',ai_provider='groq',updated_at=now();

  update public.clinical_case_posts
  set qcm_question=trim(v_first->>'question'),qcm_options=v_first->'options',correct_index=(v_first->>'correct_index')::smallint,
      correction=v_first->>'correction',question_topic=trim(v_first->>'topic'),generation_source='openai',qcm_ai_provider='groq',updated_at=now()
  where id=p_post_id;
  if not found then raise exception 'post_not_found'; end if;
end;
$$;

revoke all on function public.clinical_case_claim_qcm_generation(uuid,uuid,boolean) from public,anon,authenticated;
revoke all on function public.clinical_case_finish_qcm_generation(uuid,boolean,text) from public,anon,authenticated;
revoke all on function public.clinical_case_commit_generated_qcms(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.clinical_case_claim_qcm_generation(uuid,uuid,boolean) to service_role;
grant execute on function public.clinical_case_finish_qcm_generation(uuid,boolean,text) to service_role;
grant execute on function public.clinical_case_commit_generated_qcms(uuid,jsonb) to service_role;

-- Clear obsolete Gemini/OpenAI failures for every published case that still lacks a complete 5-QCM set.
update public.clinical_case_posts p
set qcm_generation_status='idle',
    qcm_generation_attempts=0,
    qcm_generation_started_at=null,
    qcm_generation_finished_at=null,
    qcm_generation_last_error=null,
    qcm_generation_retry_after=null,
    qcm_ai_provider=null
where p.published_at is not null
  and (select count(*) from public.clinical_case_qcms q where q.post_id=p.id and q.generation_source='openai')<>5;

update public.clinical_case_qcm_generation_jobs j
set status='pending',attempt_count=0,started_at=null,finished_at=null,last_error_code=null,retry_after=null,updated_at=now()
where (select count(*) from public.clinical_case_qcms q where q.post_id=j.post_id and q.generation_source='openai')<>5;
