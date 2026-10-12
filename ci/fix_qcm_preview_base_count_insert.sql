CREATE OR REPLACE FUNCTION public.clinical_case_stage_qcm_preview(p_post_id uuid, p_user_id uuid, p_qcms jsonb, p_difficulty text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  values (p_post_id,p_user_id,p_qcms,v_qty,p_difficulty,v_count)
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
$function$

