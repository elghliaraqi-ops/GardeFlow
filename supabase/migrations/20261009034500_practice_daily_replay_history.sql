-- Practice: archived official daily challenges may be replayed without altering
-- the immutable original /10, its calendar status, or any global QCM ranking.
create table if not exists public.practice_daily_replay_attempts (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  challenge_date date not null,
  mode text not null check (mode in ('cours','cas_clinique')),
  answers jsonb not null check (jsonb_typeof(answers)='array' and jsonb_array_length(answers)=10),
  score smallint not null check (score between 0 and 10),
  completed_at timestamptz not null default now(),
  foreign key(challenge_date,mode)
    references public.practice_daily_challenges(challenge_date,mode)
);
create index if not exists practice_daily_replay_history_idx
  on public.practice_daily_replay_attempts(user_id,challenge_date desc,completed_at desc);

alter table public.practice_daily_replay_attempts enable row level security;
revoke all on public.practice_daily_replay_attempts from public,anon,authenticated;
grant select,insert on public.practice_daily_replay_attempts to service_role;

create or replace function public.practice_daily_history(
  p_limit integer default 40,
  p_offset integer default 0
)
returns table(
  challenge_date date,
  mode text,
  official_score smallint,
  case_title text,
  replay_count bigint,
  last_replay_score smallint,
  last_replay_at timestamptz,
  completed_at timestamptz
)
language plpgsql stable security definer
set search_path=public,pg_temp
as $$
declare v_uid uuid:=auth.uid();
begin
  if v_uid is null or not exists (
    select 1 from public.profiles p where p.id=v_uid and p.account_status='active'
  ) then raise exception 'active_account_required';end if;
  if p_limit is null or p_limit<1 or p_limit>100
    or p_offset is null or p_offset<0 or p_offset>10000 then
    raise exception 'invalid_history_page';
  end if;
  return query
  select a.challenge_date, a.mode, a.score,
    coalesce(nullif(c.case_title,''),case when a.mode='cours'
      then 'Défi de cours' else 'Cas clinique' end),
    (select count(*) from public.practice_daily_replay_attempts r
      where r.user_id=v_uid and r.challenge_date=a.challenge_date),
    (select r.score from public.practice_daily_replay_attempts r
      where r.user_id=v_uid and r.challenge_date=a.challenge_date
      order by r.completed_at desc,r.id desc limit 1),
    (select r.completed_at from public.practice_daily_replay_attempts r
      where r.user_id=v_uid and r.challenge_date=a.challenge_date
      order by r.completed_at desc,r.id desc limit 1),
    a.completed_at
  from public.practice_daily_attempts a
  join public.practice_daily_challenges c
    on c.challenge_date=a.challenge_date and c.mode=a.mode
  where a.user_id=v_uid
  order by a.challenge_date desc
  limit p_limit offset p_offset;
end;
$$;

create or replace function public.practice_daily_replay_open(p_day date)
returns jsonb
language plpgsql stable security definer
set search_path=public,pg_temp
as $$
declare
  v_uid uuid:=auth.uid();
  v_original public.practice_daily_attempts%rowtype;
  v_challenge public.practice_daily_challenges%rowtype;
  v_questions jsonb;
  v_count bigint;
begin
  if v_uid is null or not exists (
    select 1 from public.profiles p where p.id=v_uid and p.account_status='active'
  ) then raise exception 'active_account_required';end if;
  if p_day is null or p_day>(now() at time zone 'Africa/Casablanca')::date
    then raise exception 'invalid_replay_day';end if;
  select * into v_original from public.practice_daily_attempts
    where user_id=v_uid and challenge_date=p_day;
  if not found then raise exception 'replay_requires_completed_daily_challenge';end if;
  select * into v_challenge from public.practice_daily_challenges
    where challenge_date=p_day and mode=v_original.mode;
  if not found then raise exception 'daily_challenge_missing';end if;

  select jsonb_agg(
    jsonb_build_object(
      'question',q.item->>'question','options',q.item->'options',
      'topic',q.item->>'topic',
      'selected_index',null,'correct_index',null,'correction',null
    ) order by q.idx
  ) into v_questions
  from jsonb_array_elements(v_challenge.questions) with ordinality as q(item,idx);
  select count(*) into v_count from public.practice_daily_replay_attempts
    where user_id=v_uid and challenge_date=p_day;

  return jsonb_build_object(
    'ready',true,'replay',true,'completed',false,
    'day',v_challenge.challenge_date,'mode',v_challenge.mode,
    'case_title',v_challenge.case_title,
    'case_stem',case when jsonb_array_length(v_challenge.case_stages)=4
      then '' else v_challenge.case_stem end,
    'case_stages',v_challenge.case_stages,
    'questions',v_questions,'score',null,
    'official_score',v_original.score,'replay_count',v_count
  );
end;
$$;

create or replace function public.practice_daily_replay_finish(
  p_day date,p_answers jsonb,p_replay_id uuid
)
returns jsonb
language plpgsql security definer
set search_path=public,pg_temp
as $$
declare
  v_uid uuid:=auth.uid();
  v_original public.practice_daily_attempts%rowtype;
  v_challenge public.practice_daily_challenges%rowtype;
  v_saved public.practice_daily_replay_attempts%rowtype;
  v_pos integer;
  v_score smallint:=0;
  v_questions jsonb;
  v_count bigint;
begin
  if v_uid is null or not exists (
    select 1 from public.profiles p where p.id=v_uid and p.account_status='active'
  ) then raise exception 'active_account_required';end if;
  if p_day is null or p_day>(now() at time zone 'Africa/Casablanca')::date
    or p_replay_id is null then raise exception 'invalid_replay_request';end if;
  if jsonb_typeof(p_answers) is distinct from 'array'
    or jsonb_array_length(p_answers)<>10 then
    raise exception 'exactly_10_answers_required';end if;

  select * into v_original from public.practice_daily_attempts
    where user_id=v_uid and challenge_date=p_day;
  if not found then raise exception 'replay_requires_completed_daily_challenge';end if;
  select * into v_challenge from public.practice_daily_challenges
    where challenge_date=p_day and mode=v_original.mode;
  if not found then raise exception 'daily_challenge_missing';end if;

  for v_pos in 0..9 loop
    if jsonb_typeof(p_answers->v_pos) is distinct from 'number'
      or (p_answers->>v_pos)!~'^[0-3]$' then
      raise exception 'invalid_answer';end if;
    if (p_answers->>v_pos)::integer=
      (v_challenge.questions->v_pos->>'correct_index')::integer then
      v_score:=v_score+1;
    end if;
  end loop;
  insert into public.practice_daily_replay_attempts
    (id,user_id,challenge_date,mode,answers,score)
  values(p_replay_id,v_uid,p_day,v_original.mode,p_answers,v_score)
  on conflict(id) do nothing;

  select * into v_saved from public.practice_daily_replay_attempts
    where id=p_replay_id and user_id=v_uid and challenge_date=p_day;
  if not found or v_saved.mode<>v_original.mode then
    raise exception 'replay_id_already_used';end if;

  select jsonb_agg(
    jsonb_build_object(
      'question',q.item->>'question','options',q.item->'options',
      'topic',q.item->>'topic',
      'selected_index',(v_saved.answers->>((q.idx-1)::integer))::integer,
      'correct_index',(q.item->>'correct_index')::integer,
      'correction',q.item->>'correction'
    ) order by q.idx
  ) into v_questions
  from jsonb_array_elements(v_challenge.questions) with ordinality as q(item,idx);
  select count(*) into v_count from public.practice_daily_replay_attempts
    where user_id=v_uid and challenge_date=p_day;

  return jsonb_build_object(
    'ready',true,'replay',true,'completed',true,
    'day',v_challenge.challenge_date,'mode',v_challenge.mode,
    'case_title',v_challenge.case_title,'case_stem',v_challenge.case_stem,
    'case_stages',v_challenge.case_stages,
    'questions',v_questions,'score',v_saved.score,
    'official_score',v_original.score,'replay_count',v_count,
    'replay_id',v_saved.id
  );
end;
$$;

revoke all on function public.practice_daily_history(integer,integer)
  from public,anon,authenticated;
revoke all on function public.practice_daily_replay_open(date)
  from public,anon,authenticated;
revoke all on function public.practice_daily_replay_finish(date,jsonb,uuid)
  from public,anon,authenticated;
grant execute on function public.practice_daily_history(integer,integer),
  public.practice_daily_replay_open(date),
  public.practice_daily_replay_finish(date,jsonb,uuid)
  to authenticated;
