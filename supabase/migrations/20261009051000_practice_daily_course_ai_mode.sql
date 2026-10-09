-- Preserve scored legacy course days and publish new AI-generated course
-- challenges as a separate mode. Never rewrite completed QCMs or corrections.
-- The daily_attempts primary key (user_id,challenge_date) still enforces one
-- OFFICIAL scored attempt per day, independent of its selected mode.
do $$
declare v_table text;v_constraint text;
begin
 for v_table,v_constraint in
  select * from (values
   ('practice_daily_challenges','practice_daily_challenges_mode_check'),
   ('practice_daily_attempts','practice_daily_attempts_mode_check'),
   ('practice_daily_generation_claims','practice_daily_generation_claims_mode_check'),
   ('practice_daily_replay_attempts','practice_daily_replay_attempts_mode_check')
  ) t(name,constraint_name)
 loop
  execute format('alter table public.%I drop constraint if exists %I',v_table,v_constraint);
  execute format(
    'alter table public.%I add constraint %I check (mode in (''cours'',''cours_ia'',''cas_clinique''))',
     v_table,v_constraint
  );
 end loop;
end;$$;

create or replace function public.practice_daily_open(p_mode text default 'cours_ia')
returns jsonb language plpgsql security definer
set search_path=public,pg_temp
as $$
declare
  v_uid uuid:=auth.uid(); v_day date:=(now() at time zone 'Africa/Casablanca')::date;
  v_mode text:=p_mode; v_attempt public.practice_daily_attempts%rowtype;
  v_challenge public.practice_daily_challenges%rowtype;
  v_public jsonb;
begin
 if v_uid is null or not exists(select 1 from public.profiles p where p.id=v_uid and p.account_status='active') then
   raise exception 'Compte actif requis.';end if;
 if v_mode not in ('cours','cours_ia','cas_clinique') then raise exception 'Mode invalide.';end if;
 select * into v_attempt from public.practice_daily_attempts where user_id=v_uid and challenge_date=v_day;
 if found then v_mode:=v_attempt.mode;end if;
 select * into v_challenge from public.practice_daily_challenges where challenge_date=v_day and mode=v_mode;
 if not found then return jsonb_build_object('ready',false,'day',v_day,'mode',v_mode);end if;
 select jsonb_agg(
  jsonb_build_object('question',q.item->>'question','options',q.item->'options','topic',q.item->>'topic',
   'selected_index',case when v_attempt.completed_at is not null then (v_attempt.answers->>((q.idx-1)::integer))::integer else null end,
   'correct_index',case when v_attempt.completed_at is not null then (q.item->>'correct_index')::integer else null end,
   'correction',case when v_attempt.completed_at is not null then q.item->>'correction' else null end
  ) order by q.idx
 ) into v_public from jsonb_array_elements(v_challenge.questions) with ordinality as q(item,idx);
 return jsonb_build_object('ready',true,'day',v_day,'mode',v_mode,
  'case_title',v_challenge.case_title,
   'case_stem',case when jsonb_array_length(v_challenge.case_stages)=4
      and v_attempt.completed_at is null then '' else v_challenge.case_stem end,
   'case_stages',v_challenge.case_stages,
  'questions',v_public,'completed',v_attempt.completed_at is not null,
  'score',case when v_attempt.completed_at is not null then v_attempt.score else null end);
end;$$;

create or replace function public.practice_daily_finish(p_mode text,p_answers jsonb)
returns jsonb language plpgsql security definer
set search_path=public,pg_temp
as $$
declare
 v_uid uuid:=auth.uid();v_day date:=(now() at time zone 'Africa/Casablanca')::date;
 v_challenge public.practice_daily_challenges%rowtype;
 v_idx integer;v_score integer:=0;v_answer integer;
 v_existing public.practice_daily_attempts%rowtype; v_question jsonb;
begin
 if v_uid is null or not exists(select 1 from public.profiles p where p.id=v_uid and p.account_status='active') then raise exception 'Authentification requise.';end if;
 if p_mode not in ('cours','cours_ia','cas_clinique') then raise exception 'Mode invalide.';end if;
 if jsonb_typeof(p_answers) is distinct from 'array' or jsonb_array_length(p_answers)<>10 then raise exception 'Il faut répondre aux 10 QCM.';end if;
 select * into v_challenge from public.practice_daily_challenges where challenge_date=v_day and mode=p_mode;
 if not found then raise exception 'Défi introuvable.';end if;
 for v_idx in 0..9 loop
   if jsonb_typeof(p_answers->v_idx) is distinct from 'number' or
      (p_answers->>v_idx)!~'^[0-3]$' then raise exception 'Réponse invalide.';end if;
   v_answer:=(p_answers->>v_idx)::integer;
   v_question:=v_challenge.questions->v_idx;
   if v_answer=(v_question->>'correct_index')::integer then v_score:=v_score+1;end if;
 end loop;
 insert into public.practice_daily_attempts(user_id,challenge_date,mode,answers,score)
 values(v_uid,v_day,p_mode,p_answers,v_score)
 on conflict(user_id,challenge_date) do nothing;
 select * into v_existing from public.practice_daily_attempts where user_id=v_uid and challenge_date=v_day;
 return public.practice_daily_open(v_existing.mode);
end;$$;

create or replace function public.practice_daily_generation_claim(p_day date,p_mode text)
returns boolean language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_count integer;
begin
 if p_day is distinct from (now() at time zone 'Africa/Casablanca')::date or
 p_mode not in ('cours','cours_ia','cas_clinique') then return false;end if;
 if exists(select 1 from public.practice_daily_challenges where challenge_date=p_day and mode=p_mode)then return false;end if;
 insert into public.practice_daily_generation_claims(challenge_date,mode,claimed_at)
 values(p_day,p_mode,now())
 on conflict(challenge_date,mode) do update set claimed_at=excluded.claimed_at
 where public.practice_daily_generation_claims.claimed_at < now()-interval '3 minutes';
 get diagnostics v_count=row_count;
 return v_count=1;
end;$$;

-- The existing SECURITY DEFINER routines keep the same signatures, RLS
-- protections, and grants as the original deployed functions.
revoke all on function public.practice_daily_open(text) from public,anon;
revoke all on function public.practice_daily_finish(text,jsonb) from public,anon;
revoke all on function public.practice_daily_generation_claim(date,text) from public,anon,authenticated;
grant execute on function public.practice_daily_open(text),
 public.practice_daily_finish(text,jsonb) to authenticated;
grant execute on function public.practice_daily_generation_claim(date,text) to service_role;
