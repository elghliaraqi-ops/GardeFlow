-- Practice QCM previews: staging is service-role only, never exposed to client.
create schema if not exists private;
create table if not exists private.practice_qcm_previews (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.clinical_case_posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  payload jsonb not null,
  quantity integer not null check (quantity in (5,10,20)),
  difficulty text not null check (difficulty in ('facile','intermediaire','avance')),
  base_count integer not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '15 minutes',
  unique(post_id,user_id)
);
alter table private.practice_qcm_previews enable row level security;
revoke all on table private.practice_qcm_previews from public,anon,authenticated;
grant select,insert,update,delete on private.practice_qcm_previews to service_role;

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
     or jsonb_array_length(p_qcms) not in (5,10,20)
  then raise exception 'invalid_qcm_payload'; end if;

  select count(*)::integer, coalesce(max(position),0)::integer
  into v_count,v_last_position
  from public.clinical_case_qcms
  where post_id=p_post_id;
  if v_count<5 or v_last_position + jsonb_array_length(p_qcms) >100 then
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
  if v_unique_count<>jsonb_array_length(p_qcms) then raise exception 'duplicate_qcm_in_batch'; end if;

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

  return v_count+jsonb_array_length(p_qcms);
end;
$$;



create or replace function public.clinical_case_stage_qcm_preview(
  p_post_id uuid, p_user_id uuid, p_qcms jsonb, p_difficulty text
)
returns uuid
language plpgsql security definer set search_path=public,pg_temp
as $$
declare
  v_post public.clinical_case_posts%rowtype;
  v_qty integer;
  v_count integer;
  v_id uuid;
  v_unique integer;
begin
  if p_user_id is null or p_post_id is null or
    p_difficulty not in ('facile','intermediaire','avance') or
    jsonb_typeof(p_qcms) is distinct from 'array' then
    raise exception 'invalid_preview_payload';
  end if;
  v_qty:=jsonb_array_length(p_qcms);
  if v_qty not in (5,10,20) then raise exception 'invalid_preview_quantity'; end if;
  select * into v_post from public.clinical_case_posts where id=p_post_id for update;
  if not found or v_post.qcm_extension_locked_until is null
    or v_post.qcm_extension_locked_until<=now() then
    raise exception 'preview_claim_required';
  end if;
  if not exists(select 1 from public.profiles p where p.id=p_user_id and p.account_status='active') or
    not (v_post.author_id=p_user_id or exists (
      select 1 from public.profiles p where p.id=p_user_id and p.role='admin' and p.account_status='active'
    )) then raise exception 'not_authorized'; end if;

  select count(*)::integer into v_count from public.clinical_case_qcms where post_id=p_post_id;
  if v_count<5 or v_count+v_qty>100 then raise exception 'qcm_limit_reached'; end if;
  select count(distinct regexp_replace(lower(trim(e.item->>'question')),'\s+',' ','g'))
  into v_unique from jsonb_array_elements(p_qcms) e(item);
  if v_unique<>v_qty then raise exception 'duplicate_qcm_in_preview'; end if;

  if exists(select 1 from jsonb_array_elements(p_qcms) e(item)
    join public.clinical_case_qcms q on q.post_id=p_post_id
      and regexp_replace(lower(trim(q.question)),'\s+',' ','g')=
          regexp_replace(lower(trim(e.item->>'question')),'\s+',' ','g')
  ) then raise exception 'duplicate_qcm_existing'; end if;

  insert into private.practice_qcm_previews (post_id,user_id,payload,quantity,difficulty,base_count)
  values (p_post_id,p_user_id,p_qcms,v_qty,p_difficulty)
  on conflict (post_id,user_id) do update
    set id=gen_random_uuid(),payload=excluded.payload,quantity=excluded.quantity,
      difficulty=excluded.difficulty,base_count=excluded.base_count,
      created_at=now(),expires_at=now()+interval '15 minutes'
  returning id into v_id;

  -- Preview is not publication: release lock; keep existing server cooldown.
  update public.clinical_case_posts
    set qcm_extension_locked_until=null,
        qcm_extension_retry_after=now()+interval '60 seconds'
  where id=p_post_id;
  return v_id;
end;
$$;

create or replace function public.clinical_case_confirm_qcm_preview(
  p_post_id uuid, p_user_id uuid, p_preview_id uuid
)
returns integer
language plpgsql security definer set search_path=public,pg_temp
as $$
declare
  v_preview private.practice_qcm_previews%rowtype;
  v_actual_count integer;
  v_new_total integer;
begin
  if p_user_id is null or p_post_id is null or p_preview_id is null then
    raise exception 'invalid_confirmation';
  end if;
  -- Lock the clinical post before reading the preview, matching staging's lock order.
  perform 1 from public.clinical_case_posts where id=p_post_id for update;
  if not found then raise exception 'case_not_found'; end if;

  select * into v_preview from private.practice_qcm_previews
   where id=p_preview_id and post_id=p_post_id and user_id=p_user_id
   for update;
  if not found or v_preview.expires_at<=now() then
    raise exception 'preview_expired_or_invalid';
  end if;

  select count(*)::integer into v_actual_count from public.clinical_case_qcms
   where post_id=p_post_id;
  if v_actual_count<>v_preview.base_count then
    raise exception 'preview_is_outdated';
  end if;

  -- Re-establish a transaction-scoped extension lock for the existing
  -- append RPC, which performs authorization, full validation and insert.
  update public.clinical_case_posts
  set qcm_extension_locked_until=now()+interval '3 minutes'
  where id=p_post_id;
  v_new_total:=public.clinical_case_append_generated_qcms(
    p_post_id,p_user_id,v_preview.payload
  );
  delete from private.practice_qcm_previews where id=p_preview_id;
  return v_new_total;
end;
$$;

create or replace function public.clinical_case_discard_qcm_preview(
  p_post_id uuid,p_user_id uuid,p_preview_id uuid
)
returns void
language plpgsql security definer set search_path=public,pg_temp
as $$
begin
  delete from private.practice_qcm_previews p where p.id=p_preview_id
    and p.post_id=p_post_id and p.user_id=p_user_id;
end;
$$;

revoke all on function public.clinical_case_stage_qcm_preview(uuid,uuid,jsonb,text) from public,anon,authenticated;
revoke all on function public.clinical_case_confirm_qcm_preview(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.clinical_case_discard_qcm_preview(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.clinical_case_stage_qcm_preview(uuid,uuid,jsonb,text) to service_role;
grant execute on function public.clinical_case_confirm_qcm_preview(uuid,uuid,uuid) to service_role;
grant execute on function public.clinical_case_discard_qcm_preview(uuid,uuid,uuid) to service_role;
