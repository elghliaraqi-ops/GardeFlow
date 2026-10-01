alter table public.clinical_case_posts
  add column if not exists qcm_generation_status text not null default 'idle',
  add column if not exists qcm_generation_attempts integer not null default 0,
  add column if not exists qcm_generation_started_at timestamptz,
  add column if not exists qcm_generation_finished_at timestamptz,
  add column if not exists qcm_generation_last_error text,
  add column if not exists qcm_generation_retry_after timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'clinical_case_posts_qcm_generation_status_check'
      and conrelid = 'public.clinical_case_posts'::regclass
  ) then
    alter table public.clinical_case_posts
      add constraint clinical_case_posts_qcm_generation_status_check
      check (qcm_generation_status in ('idle','running','ready','failed'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'clinical_case_posts_qcm_generation_attempts_check'
      and conrelid = 'public.clinical_case_posts'::regclass
  ) then
    alter table public.clinical_case_posts
      add constraint clinical_case_posts_qcm_generation_attempts_check
      check (qcm_generation_attempts >= 0 and qcm_generation_attempts <= 100);
  end if;
end $$;

create index if not exists idx_clinical_case_posts_qcm_generation_status
  on public.clinical_case_posts(qcm_generation_status, qcm_generation_retry_after);

update public.clinical_case_posts c
set qcm_generation_status = case
      when (select count(*) from public.clinical_case_qcms q where q.post_id=c.id and q.generation_source='openai') = 5 then 'ready'
      else 'idle'
    end,
    qcm_generation_finished_at = case
      when (select count(*) from public.clinical_case_qcms q where q.post_id=c.id and q.generation_source='openai') = 5 then coalesce(c.qcm_generation_finished_at, now())
      else c.qcm_generation_finished_at
    end,
    qcm_generation_retry_after = null,
    qcm_generation_last_error = null;

create or replace function public.clinical_case_claim_qcm_generation(
  p_post_id uuid,
  p_force boolean default false
)
returns table(
  claimed boolean,
  status text,
  attempts integer,
  retry_after timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.clinical_case_posts%rowtype;
  v_count integer;
  v_attempts integer;
  v_last_attempt timestamptz;
begin
  select * into r
  from public.clinical_case_posts
  where id = p_post_id
  for update;

  if not found then
    return query select false, 'missing'::text, 0, null::timestamptz;
    return;
  end if;

  select count(*)::integer into v_count
  from public.clinical_case_qcms q
  where q.post_id = p_post_id and q.generation_source = 'openai';

  if v_count = 5 then
    update public.clinical_case_posts
    set qcm_generation_status='ready',
        qcm_generation_finished_at=coalesce(qcm_generation_finished_at, now()),
        qcm_generation_retry_after=null,
        qcm_generation_last_error=null
    where id=p_post_id;
    return query select false, 'ready'::text, r.qcm_generation_attempts, null::timestamptz;
    return;
  end if;

  if not p_force and r.qcm_generation_status='running'
     and r.qcm_generation_started_at is not null
     and r.qcm_generation_started_at > now() - interval '2 minutes' then
    return query select false, 'running'::text, r.qcm_generation_attempts,
      r.qcm_generation_started_at + interval '2 minutes';
    return;
  end if;

  if not p_force and r.qcm_generation_retry_after is not null
     and r.qcm_generation_retry_after > now() then
    return query select false, 'failed'::text, r.qcm_generation_attempts, r.qcm_generation_retry_after;
    return;
  end if;

  v_last_attempt := coalesce(r.qcm_generation_started_at, r.qcm_generation_finished_at);
  if not p_force and r.qcm_generation_attempts >= 3
     and v_last_attempt is not null
     and v_last_attempt > now() - interval '10 minutes' then
    return query select false, 'failed'::text, r.qcm_generation_attempts,
      greatest(coalesce(r.qcm_generation_retry_after, now()), v_last_attempt + interval '10 minutes');
    return;
  end if;

  v_attempts := case
    when v_last_attempt is null or v_last_attempt <= now() - interval '10 minutes' then 1
    else least(r.qcm_generation_attempts + 1, 100)
  end;

  update public.clinical_case_posts
  set qcm_generation_status='running',
      qcm_generation_attempts=v_attempts,
      qcm_generation_started_at=now(),
      qcm_generation_finished_at=null,
      qcm_generation_last_error=null,
      qcm_generation_retry_after=null
  where id=p_post_id;

  return query select true, 'running'::text, v_attempts, null::timestamptz;
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
set search_path = public
as $$
declare
  v_attempts integer;
  v_delay_seconds integer;
  v_error text;
begin
  select qcm_generation_attempts into v_attempts
  from public.clinical_case_posts
  where id=p_post_id
  for update;

  if not found then return; end if;

  if p_success then
    update public.clinical_case_posts
    set qcm_generation_status='ready',
        qcm_generation_finished_at=now(),
        qcm_generation_last_error=null,
        qcm_generation_retry_after=null
    where id=p_post_id;
    return;
  end if;

  v_delay_seconds := least(180, case
    when coalesce(v_attempts,1) <= 1 then 15
    when v_attempts = 2 then 45
    else 120
  end);
  v_error := left(regexp_replace(coalesce(p_error_code,'generation_failed'), '[^a-zA-Z0-9_:-]', '', 'g'), 80);
  if v_error = '' then v_error := 'generation_failed'; end if;

  update public.clinical_case_posts
  set qcm_generation_status='failed',
      qcm_generation_finished_at=now(),
      qcm_generation_last_error=v_error,
      qcm_generation_retry_after=now() + make_interval(secs => v_delay_seconds)
  where id=p_post_id;
end;
$$;

revoke all on function public.clinical_case_claim_qcm_generation(uuid,boolean) from public, anon, authenticated;
revoke all on function public.clinical_case_finish_qcm_generation(uuid,boolean,text) from public, anon, authenticated;
grant execute on function public.clinical_case_claim_qcm_generation(uuid,boolean) to service_role;
grant execute on function public.clinical_case_finish_qcm_generation(uuid,boolean,text) to service_role;
