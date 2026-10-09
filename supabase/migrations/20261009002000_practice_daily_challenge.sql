-- Daily Practice: one scored 10-question session per user per Casablanca day.
-- Question keys and explanations remain server-side until submission.
create table if not exists public.practice_daily_challenges (
  challenge_date date not null,
  mode text not null check (mode in ('cours','cas_clinique')),
  case_title text not null default '',
  case_stem text not null default '',
  questions jsonb not null check (jsonb_typeof(questions)='array' and jsonb_array_length(questions)=10),
  published_at timestamptz not null default now(),
  primary key(challenge_date,mode)
);
create table if not exists public.practice_daily_attempts (
  user_id uuid not null references auth.users(id) on delete cascade,
  challenge_date date not null,
  mode text not null check (mode in ('cours','cas_clinique')),
  answers jsonb not null check(jsonb_typeof(answers)='array' and jsonb_array_length(answers)=10),
  score smallint not null check(score between 0 and 10),
  completed_at timestamptz not null default now(),
  primary key(user_id,challenge_date),
  foreign key(challenge_date,mode) references public.practice_daily_challenges(challenge_date,mode)
);
create index if not exists practice_daily_attempts_user_date_desc on public.practice_daily_attempts(user_id,challenge_date desc);

create table if not exists public.practice_daily_reminders (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.practice_daily_challenges enable row level security;
alter table public.practice_daily_attempts enable row level security;
alter table public.practice_daily_reminders enable row level security;
revoke all on public.practice_daily_challenges,public.practice_daily_attempts from public,anon,authenticated;
revoke all on public.practice_daily_reminders from public,anon;
grant select,insert,update,delete on public.practice_daily_reminders to authenticated;
create policy practice_daily_reminders_select on public.practice_daily_reminders for select to authenticated using(user_id=(select auth.uid()));
create policy practice_daily_reminders_insert on public.practice_daily_reminders for insert to authenticated with check(user_id=(select auth.uid()));
create policy practice_daily_reminders_update on public.practice_daily_reminders for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));

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
   'selected_index',case when v_attempt.completed_at is not null then (v_attempt.answers->>(q.idx-1))::integer else null end,
   'correct_index',case when v_attempt.completed_at is not null then (q.item->>'correct_index')::integer else null end,
   'correction',case when v_attempt.completed_at is not null then q.item->>'correction' else null end
  ) order by q.idx
 ) into v_public from jsonb_array_elements(v_challenge.questions) with ordinality as q(item,idx);
 return jsonb_build_object('ready',true,'day',v_day,'mode',v_mode,
  'case_title',v_challenge.case_title,'case_stem',v_challenge.case_stem,
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
 if p_mode not in ('cours','cas_clinique') then raise exception 'Mode invalide.';end if;
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

create or replace function public.practice_daily_calendar(p_month date)
returns table(challenge_date date,mode text,score smallint,completed_at timestamptz)
language plpgsql stable security definer
set search_path=public,pg_temp
as $$
declare v_uid uuid:=auth.uid();
begin
 if v_uid is null or not exists(select 1 from public.profiles p where p.id=v_uid and p.account_status='active') then raise exception 'Compte actif requis.';end if;
 if p_month is null or p_month<date_trunc('month',(now() at time zone 'Africa/Casablanca')::date)::date-interval '24 months'
  or p_month>date_trunc('month',(now() at time zone 'Africa/Casablanca')::date)::date+interval '12 months'
  then raise exception 'Mois hors période.';end if;
 return query select a.challenge_date,a.mode,a.score,a.completed_at from public.practice_daily_attempts a
 where a.user_id=v_uid and a.challenge_date>=date_trunc('month',p_month)::date
 and a.challenge_date<(date_trunc('month',p_month)+interval '1 month')::date order by a.challenge_date;
end;$$;

revoke all on function public.practice_daily_open(text) from public,anon;
revoke all on function public.practice_daily_finish(text,jsonb) from public,anon;
revoke all on function public.practice_daily_calendar(date) from public,anon;
grant execute on function public.practice_daily_open(text),public.practice_daily_finish(text,jsonb),public.practice_daily_calendar(date) to authenticated;
