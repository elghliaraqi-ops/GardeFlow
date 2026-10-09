-- AI-only daily challenges with historic local quizzes kept in archives.
-- When a user has already scored today's old local challenge, their new
-- AI quiz is available as unranked training with unchanged official score.
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
 -- The historic first attempt stays immutable, but local QCMs may no longer
 -- appear in the AI-only daily screen.
 if found and p_mode='cours_ia' and v_attempt.mode<>'cours_ia' then
  select * into v_challenge from public.practice_daily_challenges
    where challenge_date=v_day and mode='cours_ia';
  if not found then
    return jsonb_build_object('ready',false,'day',v_day,'mode','cours_ia',
      'completed',false,'replay',true,'official_score',v_attempt.score);
  end if;
  select jsonb_agg(jsonb_build_object(
    'question',q.item->>'question','options',q.item->'options',
    'topic',q.item->>'topic','selected_index',null,
    'correct_index',null,'correction',null
  ) order by q.idx)
  into v_public
  from jsonb_array_elements(v_challenge.questions) with ordinality as q(item,idx);
  return jsonb_build_object(
    'ready',true,'day',v_day,'mode','cours_ia',
    'case_title','','case_stem','','case_stages','[]'::jsonb,
    'questions',v_public,'completed',false,'replay',true,
    'score',null,'official_score',v_attempt.score
  );
 end if;
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
 if p_mode <> 'cours_ia' then raise exception 'daily_challenge_ai_only';end if;
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
 -- People who finished the old daily quiz can still try today's AI quiz
 -- as unranked practice. Never rewrite that initial /10, streak or XP.
 select * into v_existing from public.practice_daily_attempts
   where user_id=v_uid and challenge_date=v_day;
 if found and v_existing.mode<>'cours_ia' then
  return jsonb_build_object(
    'ready',true,'day',v_day,'mode','cours_ia',
    'completed',true,'replay',true,'official_score',v_existing.score,
    'score',v_score,'case_title','','case_stem','','case_stages','[]'::jsonb,
    'questions',(
      select jsonb_agg(jsonb_build_object(
        'question',q.item->>'question','options',q.item->'options',
        'topic',q.item->>'topic',
        'selected_index',(p_answers->>((q.idx-1)::integer))::integer,
        'correct_index',(q.item->>'correct_index')::integer,
        'correction',q.item->>'correction'
      ) order by q.idx)
      from jsonb_array_elements(v_challenge.questions) with ordinality as q(item,idx)
    )
  );
 end if;
 insert into public.practice_daily_attempts(user_id,challenge_date,mode,answers,score)
 values(v_uid,v_day,p_mode,p_answers,v_score)
 on conflict(user_id,challenge_date) do nothing;
 select * into v_existing from public.practice_daily_attempts where user_id=v_uid and challenge_date=v_day;
 return public.practice_daily_open(v_existing.mode);
end;$$;

revoke all on function public.practice_daily_open(text) from public,anon;
revoke all on function public.practice_daily_finish(text,jsonb) from public,anon;
grant execute on function public.practice_daily_open(text),
 public.practice_daily_finish(text,jsonb) to authenticated;
