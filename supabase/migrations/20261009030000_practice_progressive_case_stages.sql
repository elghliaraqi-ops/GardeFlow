-- 4 sequential, pedagogical disclosures for the 10-QCM fictional daily case.
-- Existing daily courses and legacy cases preserve their old rendering.
alter table public.practice_daily_challenges
add column if not exists case_stages jsonb not null default '[]'::jsonb;

alter table public.practice_daily_challenges
drop constraint if exists practice_daily_challenges_case_stages_check;
alter table public.practice_daily_challenges
add constraint practice_daily_challenges_case_stages_check
check (
  jsonb_typeof(case_stages)='array'
  and jsonb_array_length(case_stages) in (0,4)
  and (
    jsonb_array_length(case_stages)=0
    or (
      case_stages->0->>'title' is not null
      and case_stages->1->>'title' is not null
      and case_stages->2->>'title' is not null
      and case_stages->3->>'title' is not null
      and case_stages->0->>'narrative' is not null
      and case_stages->1->>'narrative' is not null
      and case_stages->2->>'narrative' is not null
      and case_stages->3->>'narrative' is not null
    )
  )
);

create or replace function public.practice_daily_open(p_mode text default 'cours')
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
 if v_mode not in ('cours','cas_clinique') then raise exception 'Mode invalide.';end if;
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

