-- Practice: allow additive 5-QCM batches without modifying or resetting existing questions.
-- Endpoint access: these three RPCs are service-role-only, called by the
-- authenticated Groq Edge function after verifying the user's identity.
alter table public.clinical_case_qcms
  drop constraint if exists clinical_case_qcms_position_check;
alter table public.clinical_case_qcms
  add constraint clinical_case_qcms_position_check
  check (position between 1 and 100);

alter table public.clinical_case_posts
  add column if not exists qcm_extension_locked_until timestamptz,
  add column if not exists qcm_extension_retry_after timestamptz;

create or replace function public.clinical_case_claim_qcm_extension(
  p_post_id uuid,
  p_user_id uuid
)
returns table (
  claimed boolean,
  status text,
  attempts integer,
  retry_after timestamptz,
  error_code text
)
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_post public.clinical_case_posts%rowtype;
  v_count integer;
begin
  select * into v_post
  from public.clinical_case_posts p
  where p.id = p_post_id
  for update;
  if not found or v_post.published_at is null then
    return query select false,'failed'::text,0,null::timestamptz,'case_not_ready'::text;
    return;
  end if;

  if p_user_id is null or not exists (
    select 1 from public.profiles prof
    where prof.id = p_user_id and prof.account_status = 'active'
  ) or not (
    v_post.author_id = p_user_id or exists (
      select 1 from public.profiles prof
      where prof.id = p_user_id and prof.role = 'admin'
        and prof.account_status = 'active'
    )
  ) then
    return query select false,'failed'::text,0,null::timestamptz,'authorization_failed'::text;
    return;
  end if;

  select count(*)::integer into v_count
  from public.clinical_case_qcms q where q.post_id=p_post_id;
  if v_count < 5 then
    return query select false,'failed'::text,0,null::timestamptz,'initial_qcms_required'::text;
    return;
  end if;
  if v_count > 95 then
    return query select false,'failed'::text,0,null::timestamptz,'qcm_limit_reached'::text;
    return;
  end if;
  if v_post.qcm_extension_locked_until > now() then
    return query select false,'running'::text,0,v_post.qcm_extension_locked_until,'generation_in_progress'::text;
    return;
  end if;
  if v_post.qcm_extension_retry_after > now() then
    return query select false,'failed'::text,0,v_post.qcm_extension_retry_after,'extension_cooldown'::text;
    return;
  end if;

  update public.clinical_case_posts
  set qcm_extension_locked_until = now() + interval '3 minutes'
  where id = p_post_id;

  return query select true,'running'::text,1,null::timestamptz,null::text;
end;
$$;

create or replace function public.clinical_case_append_generated_qcms(
  p_post_id uuid,
  p_user_id uuid,
  p_qcms jsonb
)
returns integer
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_post public.clinical_case_posts%rowtype;
  v_count integer;
  v_last_position integer;
  v_unique_count integer;
  v_item jsonb;
begin
  select * into v_post from public.clinical_case_posts
  where id=p_post_id for update;
  if not found or p_user_id is null or not (
    v_post.author_id = p_user_id or exists (
      select 1 from public.profiles prof
      where prof.id=p_user_id and prof.role='admin'
        and prof.account_status='active'
    )
  ) then raise exception 'not_authorized'; end if;
  if not exists (
    select 1 from public.profiles prof
    where prof.id=p_user_id and prof.account_status='active'
  ) then raise exception 'account_inactive'; end if;

  if v_post.qcm_extension_locked_until is null
     or v_post.qcm_extension_locked_until <= now()
  then raise exception 'extension_claim_required'; end if;

  if jsonb_typeof(p_qcms) is distinct from 'array'
     or jsonb_array_length(p_qcms) <> 5
  then raise exception 'invalid_qcm_payload'; end if;

  select count(*)::integer, coalesce(max(position),0)::integer
  into v_count,v_last_position
  from public.clinical_case_qcms
  where post_id=p_post_id;
  if v_count<5 or v_last_position>95 then
    raise exception 'qcm_count_not_supported';
  end if;

  for v_item in select value from jsonb_array_elements(p_qcms) loop
    if length(trim(coalesce(v_item->>'question',''))) < 12
       or length(trim(coalesce(v_item->>'correction',''))) < 20
       or position('§SOURCES§' in coalesce(v_item->>'correction',''))=0
       or jsonb_typeof(v_item->'options') is distinct from 'array'
       or jsonb_array_length(v_item->'options')<>4
       or (v_item->>'correct_index')::integer not between 0 and 3
       or length(trim(coalesce(v_item->>'topic','')))=0
    then raise exception 'invalid_qcm_payload'; end if;
  end loop;

  select count(distinct regexp_replace(lower(trim(e.item->>'question')),'\s+',' ','g'))
  into v_unique_count
  from jsonb_array_elements(p_qcms) e(item);
  if v_unique_count<>5 then raise exception 'duplicate_qcm_in_batch'; end if;

  if exists (
    select 1 from jsonb_array_elements(p_qcms) e(item)
    join public.clinical_case_qcms old on old.post_id=p_post_id
     and regexp_replace(lower(trim(old.question)),'\s+',' ','g') =
         regexp_replace(lower(trim(e.item->>'question')),'\s+',' ','g')
  ) then raise exception 'duplicate_qcm_existing'; end if;

  insert into public.clinical_case_qcms(
    post_id,position,question,options,correct_index,correction,
    topic,generation_source,ai_provider,updated_at
  )
  select p_post_id,(v_last_position+e.ordinality)::smallint,
    trim(e.item->>'question'),e.item->'options',
    (e.item->>'correct_index')::smallint,e.item->>'correction',
    trim(e.item->>'topic'),'openai','groq',now()
  from jsonb_array_elements(p_qcms) with ordinality as e(item,ordinality)
  order by e.ordinality;

  update public.clinical_case_posts
  set qcm_extension_locked_until=null,
      qcm_extension_retry_after=now()+interval '2 minutes'
  where id=p_post_id;

  return v_count+5;
end;
$$;

create or replace function public.clinical_case_finish_qcm_extension(
  p_post_id uuid,
  p_success boolean,
  p_error_code text default null
)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  -- A successful append closes its own claim transactionally. Avoid
  -- resetting its cooldown or touching the existing generation status.
  if p_success then return; end if;
  update public.clinical_case_posts
  set qcm_extension_locked_until=null,
      qcm_extension_retry_after=now()+interval '45 seconds'
  where id=p_post_id and qcm_extension_locked_until is not null;
end;
$$;

revoke all on function public.clinical_case_claim_qcm_extension(uuid,uuid) from public,anon,authenticated;
revoke all on function public.clinical_case_append_generated_qcms(uuid,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.clinical_case_finish_qcm_extension(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.clinical_case_claim_qcm_extension(uuid,uuid) to service_role;
grant execute on function public.clinical_case_append_generated_qcms(uuid,uuid,jsonb) to service_role;
grant execute on function public.clinical_case_finish_qcm_extension(uuid,boolean,text) to service_role;
