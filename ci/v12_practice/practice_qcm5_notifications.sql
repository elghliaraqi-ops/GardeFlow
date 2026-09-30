-- GardeFlow Practice — 5 QCM par cas + support des notifications Practice.
-- Migration additive et rétrocompatible : les anciens champs QCM du post restent
-- disponibles pour les anciennes versions de l'application.

begin;

create table if not exists public.clinical_case_qcms (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.clinical_case_posts(id) on delete cascade,
  position smallint not null check (position between 1 and 5),
  question text not null,
  options jsonb not null check (jsonb_typeof(options)='array' and jsonb_array_length(options)=4),
  correct_index smallint not null check (correct_index between 0 and 3),
  correction text not null,
  topic text not null,
  generation_source text not null default 'fallback' check (generation_source in ('fallback','openai')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(post_id, position)
);

create index if not exists clinical_case_qcms_post_position_idx
  on public.clinical_case_qcms(post_id, position);

create table if not exists public.clinical_case_qcm_answers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  qcm_id uuid not null references public.clinical_case_qcms(id) on delete cascade,
  selected_index smallint not null check (selected_index between 0 and 3),
  is_correct boolean not null,
  answered_at timestamptz not null default now(),
  unique(user_id, qcm_id)
);

create index if not exists clinical_case_qcm_answers_user_answered_idx
  on public.clinical_case_qcm_answers(user_id, answered_at desc);
create index if not exists clinical_case_qcm_answers_qcm_idx
  on public.clinical_case_qcm_answers(qcm_id);

-- Déduplication des notifications Practice envoyées par send-push.
create table if not exists public.practice_push_receipts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null,
  resource_id text not null,
  sent_at timestamptz not null default now(),
  unique(user_id, kind, resource_id)
);

alter table public.clinical_case_qcms enable row level security;
alter table public.clinical_case_qcm_answers enable row level security;
alter table public.practice_push_receipts enable row level security;

-- Les lectures/écritures QCM passent par des RPC SECURITY DEFINER afin de ne
-- jamais exposer directement la bonne réponse avant l'enregistrement du choix.
revoke all on public.clinical_case_qcms from anon, authenticated;
revoke all on public.clinical_case_qcm_answers from anon, authenticated;
revoke all on public.practice_push_receipts from anon, authenticated;

create or replace function public.clinical_case_upsert_fallback_qcm(
  p_post_id uuid,
  p_position integer,
  p_question text,
  p_correct text,
  p_d1 text,
  p_d2 text,
  p_d3 text,
  p_correction text,
  p_topic text
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_rotation integer := mod(abs(hashtext(p_post_id::text || ':' || p_position::text)), 4);
  v_options jsonb;
  v_correct_index smallint;
begin
  if v_rotation = 0 then
    v_options := jsonb_build_array(p_correct,p_d1,p_d2,p_d3); v_correct_index := 0;
  elsif v_rotation = 1 then
    v_options := jsonb_build_array(p_d1,p_correct,p_d2,p_d3); v_correct_index := 1;
  elsif v_rotation = 2 then
    v_options := jsonb_build_array(p_d1,p_d2,p_correct,p_d3); v_correct_index := 2;
  else
    v_options := jsonb_build_array(p_d1,p_d2,p_d3,p_correct); v_correct_index := 3;
  end if;

  insert into public.clinical_case_qcms(
    post_id,position,question,options,correct_index,correction,topic,generation_source,updated_at
  ) values (
    p_post_id,p_position,p_question,v_options,v_correct_index,p_correction,p_topic,'fallback',now()
  )
  on conflict(post_id,position) do update set
    question=excluded.question,
    options=excluded.options,
    correct_index=excluded.correct_index,
    correction=excluded.correction,
    topic=excluded.topic,
    generation_source='fallback',
    updated_at=now();
end;
$function$;

create or replace function public.clinical_case_seed_qcms(p_post_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  c public.clinical_case_posts%rowtype;
  v_assessment text;
  v_plan text;
  v_imaging text;
  v_exam text;
  v_orientation text;
  v_correction text;
begin
  select * into c from public.clinical_case_posts where id=p_post_id;
  if not found then return; end if;

  -- Une modification du cas invalide pédagogiquement les anciennes réponses.
  delete from public.clinical_case_qcm_answers
  where qcm_id in (select id from public.clinical_case_qcms where post_id=p_post_id);

  v_assessment := coalesce(nullif(c.assessment,''), nullif(c.presentation,''), 'Synthèse non précisée');
  v_plan := coalesce(nullif(c.plan,''), 'Prise en charge non précisée dans le dossier');
  v_imaging := coalesce(nullif(c.imaging_conclusion,''), nullif(c.complementary_exams,''), 'Aucune imagerie contributive documentée');
  v_exam := coalesce(nullif(c.clinical_exam,''), 'Examen clinique non détaillé');
  v_orientation := coalesce(nullif(c.disposition,''), 'Orientation non précisée');
  v_correction := coalesce(nullif(c.correction,''), 'Correction basée sur les éléments documentés dans le cas.');

  perform public.clinical_case_upsert_fallback_qcm(
    c.id,1,c.qcm_question,
    c.qcm_options->>c.correct_index,
    c.qcm_options->>((c.correct_index+1)%4),
    c.qcm_options->>((c.correct_index+2)%4),
    c.qcm_options->>((c.correct_index+3)%4),
    v_correction,c.question_topic
  );

  perform public.clinical_case_upsert_fallback_qcm(
    c.id,2,'Quelle synthèse clinique est la plus cohérente avec les éléments documentés dans ce cas ?',
    left(v_assessment,320),
    'Le dossier ne permet de retenir aucune hypothèse clinique',
    'Un diagnostic sans rapport avec les éléments présentés',
    'Une conclusion opposée aux données cliniques documentées',
    'La synthèse doit être confrontée au motif, à l’histoire, à l’examen et aux examens complémentaires documentés. ' || left(v_correction,1200),
    'synthese'
  );

  perform public.clinical_case_upsert_fallback_qcm(
    c.id,3,'Parmi les propositions suivantes, quelle conduite est la plus proche de la prise en charge documentée ?',
    left(v_plan,320),
    'Aucune prise en charge ni surveillance',
    'Sortie immédiate sans réévaluation',
    'Traitement sans lien avec les données du cas',
    'La conduite retenue doit répondre aux éléments cliniques du patient et à leur niveau de gravité. ' || left(v_correction,1200),
    'prise_en_charge'
  );

  perform public.clinical_case_upsert_fallback_qcm(
    c.id,4,'Quel élément paraclinique ou d’imagerie doit être intégré au raisonnement pour ce cas ?',
    left(v_imaging,320),
    'Un résultat normal non documenté dans le cas',
    'Une anomalie radiologique sans rapport avec la présentation',
    'Un examen non réalisé présenté comme positif',
    'L’interprétation doit rester limitée aux examens réellement documentés et être mise en perspective avec la clinique. ' || left(v_correction,1200),
    case when c.imaging_conclusion<>'' then 'imagerie' else 'examen' end
  );

  perform public.clinical_case_upsert_fallback_qcm(
    c.id,5,'Quelle orientation est cohérente avec la prise en charge effectivement documentée dans ce cas ?',
    left(v_orientation,320),
    'Hospitalisation systématique quel que soit le contexte',
    'Sortie systématique sans critère clinique',
    'Orientation vers un service sans rapport avec le cas',
    'L’orientation dépend de la gravité, des résultats disponibles, de la réponse au traitement et du besoin éventuel d’un avis spécialisé. ' || left(v_correction,1200),
    'orientation'
  );
end;
$function$;

create or replace function public.clinical_case_qcms_sync_trigger()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  perform public.clinical_case_seed_qcms(new.id);
  return new;
end;
$function$;

drop trigger if exists trg_clinical_case_qcms_sync on public.clinical_case_posts;
create trigger trg_clinical_case_qcms_sync
after insert or update of qcm_question,qcm_options,correct_index,correction,question_topic,generation_source
on public.clinical_case_posts
for each row execute function public.clinical_case_qcms_sync_trigger();

-- Backfill immédiat de 5 QCM pour tous les cas existants. L'Edge Function IA
-- remplacera ces fallbacks par 5 questions de raisonnement clinique.
select public.clinical_case_seed_qcms(id) from public.clinical_case_posts;

-- Conserver les réponses historiques comme réponse au QCM n°1.
insert into public.clinical_case_qcm_answers(user_id,qcm_id,selected_index,is_correct,answered_at)
select a.user_id,q.id,a.selected_index,a.is_correct,a.answered_at
from public.clinical_case_qcm_attempts a
join public.clinical_case_qcms q on q.post_id=a.post_id and q.position=1
on conflict(user_id,qcm_id) do nothing;

-- Compatibilité descendante : une réponse d'un ancien client est reflétée sur
-- le nouveau QCM n°1.
create or replace function public.clinical_case_mirror_legacy_attempt()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_qcm uuid;
begin
  select id into v_qcm from public.clinical_case_qcms where post_id=new.post_id and position=1;
  if v_qcm is not null then
    insert into public.clinical_case_qcm_answers(user_id,qcm_id,selected_index,is_correct,answered_at)
    values(new.user_id,v_qcm,new.selected_index,new.is_correct,new.answered_at)
    on conflict(user_id,qcm_id) do nothing;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_clinical_case_mirror_legacy_attempt on public.clinical_case_qcm_attempts;
create trigger trg_clinical_case_mirror_legacy_attempt
after insert on public.clinical_case_qcm_attempts
for each row execute function public.clinical_case_mirror_legacy_attempt();

-- Et inversement, le QCM n°1 reste visible comme répondu dans un ancien client.
create or replace function public.clinical_case_mirror_first_qcm_answer()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_post uuid; v_position smallint;
begin
  select post_id,position into v_post,v_position from public.clinical_case_qcms where id=new.qcm_id;
  if v_position=1 then
    insert into public.clinical_case_qcm_attempts(user_id,post_id,selected_index,is_correct,answered_at)
    values(new.user_id,v_post,new.selected_index,new.is_correct,new.answered_at)
    on conflict(user_id,post_id) do nothing;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_clinical_case_mirror_first_qcm_answer on public.clinical_case_qcm_answers;
create trigger trg_clinical_case_mirror_first_qcm_answer
after insert on public.clinical_case_qcm_answers
for each row execute function public.clinical_case_mirror_first_qcm_answer();

-- Nouveau feed : qcms contient jusqu'à 5 questions. Bonne réponse et correction
-- ne sont incluses qu'après réponse pour le nouveau client.
drop function if exists public.clinical_case_feed(integer,integer);
create function public.clinical_case_feed(
  p_offset integer default 0,
  p_limit integer default 20
)
returns table(
  id uuid,
  age_band text,
  sex text,
  presentation text,
  history text,
  clinical_exam text,
  complementary_exams text,
  imaging_conclusion text,
  assessment text,
  plan text,
  disposition text,
  specialist_service text,
  qcm_question text,
  qcm_options jsonb,
  correct_index smallint,
  correction text,
  question_topic text,
  generation_source text,
  published_at timestamptz,
  my_selected_index smallint,
  my_is_correct boolean,
  qcms jsonb
)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare v_uid uuid:=auth.uid();
begin
  if v_uid is null then raise exception 'Clinical cases: authentification requise.'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_uid and p.account_status='active') then
    raise exception 'Clinical cases: compte non actif.';
  end if;

  return query
  select
    c.id,c.age_band,c.sex,c.presentation,c.history,c.clinical_exam,c.complementary_exams,
    c.imaging_conclusion,c.assessment,c.plan,c.disposition,c.specialist_service,
    c.qcm_question,c.qcm_options,c.correct_index,c.correction,c.question_topic,
    c.generation_source,c.published_at,legacy.selected_index,legacy.is_correct,
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',q.id,
          'position',q.position,
          'question',q.question,
          'options',q.options,
          'correct_index',case when ans.id is null then null else q.correct_index end,
          'correction',case when ans.id is null then '' else q.correction end,
          'topic',q.topic,
          'generation_source',q.generation_source,
          'my_selected_index',ans.selected_index,
          'my_is_correct',ans.is_correct,
          'answered_at',ans.answered_at
        ) order by q.position
      )
      from public.clinical_case_qcms q
      left join public.clinical_case_qcm_answers ans
        on ans.qcm_id=q.id and ans.user_id=v_uid
      where q.post_id=c.id
    ),'[]'::jsonb)
  from public.clinical_case_posts c
  left join public.clinical_case_qcm_attempts legacy
    on legacy.post_id=c.id and legacy.user_id=v_uid
  order by c.published_at desc,c.id desc
  offset greatest(coalesce(p_offset,0),0)
  limit least(greatest(coalesce(p_limit,20),1),50);
end;
$function$;

grant execute on function public.clinical_case_feed(integer,integer) to authenticated;

create or replace function public.clinical_case_submit_qcm_answer(
  p_qcm_id uuid,
  p_selected_index smallint
)
returns table(
  selected_index smallint,
  is_correct boolean,
  answered_at timestamptz,
  correct_index smallint,
  correction text,
  post_id uuid,
  case_answered bigint,
  case_correct bigint
)
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_correct smallint;
  v_post uuid;
begin
  if v_uid is null then raise exception 'Authentification requise.'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_uid and p.account_status='active') then
    raise exception 'Compte non actif.';
  end if;
  if p_selected_index is null or p_selected_index<0 or p_selected_index>3 then
    raise exception 'Réponse QCM invalide.';
  end if;

  select q.correct_index,q.post_id into v_correct,v_post
  from public.clinical_case_qcms q where q.id=p_qcm_id;
  if v_correct is null then raise exception 'QCM introuvable.'; end if;

  insert into public.clinical_case_qcm_answers(user_id,qcm_id,selected_index,is_correct)
  values(v_uid,p_qcm_id,p_selected_index,p_selected_index=v_correct)
  on conflict(user_id,qcm_id) do nothing;

  perform public.practice_refresh_my_achievements();

  return query
  select
    a.selected_index,a.is_correct,a.answered_at,q.correct_index,q.correction,q.post_id,
    (select count(*) from public.clinical_case_qcm_answers aa join public.clinical_case_qcms qq on qq.id=aa.qcm_id where aa.user_id=v_uid and qq.post_id=q.post_id),
    (select count(*) from public.clinical_case_qcm_answers aa join public.clinical_case_qcms qq on qq.id=aa.qcm_id where aa.user_id=v_uid and qq.post_id=q.post_id and aa.is_correct)
  from public.clinical_case_qcm_answers a
  join public.clinical_case_qcms q on q.id=a.qcm_id
  where a.user_id=v_uid and a.qcm_id=p_qcm_id;
end;
$function$;

grant execute on function public.clinical_case_submit_qcm_answer(uuid,smallint) to authenticated;

create or replace function public.clinical_case_qcm_summary(p_period text default 'month'::text)
returns table(answered bigint,correct bigint,accuracy numeric)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare v_uid uuid:=auth.uid(); v_start timestamptz; v_end timestamptz;
begin
  if v_uid is null then raise exception 'Authentification requise.'; end if;
  if p_period not in('month','year','all') then raise exception 'Période QCM invalide.'; end if;
  if p_period='month' then
    v_start:=date_trunc('month',now() at time zone 'Africa/Casablanca') at time zone 'Africa/Casablanca';
    v_end:=(date_trunc('month',now() at time zone 'Africa/Casablanca')+interval '1 month') at time zone 'Africa/Casablanca';
  elsif p_period='year' then
    v_start:=date_trunc('year',now() at time zone 'Africa/Casablanca') at time zone 'Africa/Casablanca';
    v_end:=(date_trunc('year',now() at time zone 'Africa/Casablanca')+interval '1 year') at time zone 'Africa/Casablanca';
  else
    v_start:='-infinity'::timestamptz; v_end:='infinity'::timestamptz;
  end if;
  return query
  select count(*)::bigint,
         count(*) filter(where a.is_correct)::bigint,
         case when count(*)=0 then 0::numeric else round(100.0*count(*) filter(where a.is_correct)/count(*),1) end
  from public.clinical_case_qcm_answers a
  where a.user_id=v_uid and a.answered_at>=v_start and a.answered_at<v_end;
end;
$function$;

create or replace function public.clinical_case_qcm_leaderboard(
  p_period text default 'month'::text,
  p_promotion smallint default null::smallint
)
returns table(rank bigint,user_id uuid,display_name text,promotion_number smallint,correct bigint,answered bigint,accuracy numeric)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare v_start timestamptz; v_end timestamptz;
begin
  if auth.uid() is null then raise exception 'Authentification requise.'; end if;
  if p_period not in('month','year') then raise exception 'Période QCM invalide.'; end if;
  if p_period='month' then
    v_start:=date_trunc('month',now() at time zone 'Africa/Casablanca') at time zone 'Africa/Casablanca';
    v_end:=(date_trunc('month',now() at time zone 'Africa/Casablanca')+interval '1 month') at time zone 'Africa/Casablanca';
  else
    v_start:=date_trunc('year',now() at time zone 'Africa/Casablanca') at time zone 'Africa/Casablanca';
    v_end:=(date_trunc('year',now() at time zone 'Africa/Casablanca')+interval '1 year') at time zone 'Africa/Casablanca';
  end if;
  return query with scores as(
    select p.id uid,
      trim(concat_ws(' ','Dr',nullif(p.prenom,''),nullif(p.nom,''))) display_name,
      p.promotion_number,
      count(*) filter(where a.is_correct)::bigint correct_count,
      count(*)::bigint answered_count,
      round(100.0*count(*) filter(where a.is_correct)/nullif(count(*),0),1) accuracy_pct
    from public.profiles p
    join public.clinical_case_qcm_answers a on a.user_id=p.id
    left join public.practice_preferences pref on pref.user_id=p.id
    where a.answered_at>=v_start and a.answered_at<v_end
      and coalesce(pref.leaderboard_opt_in,true)
      and coalesce(p.account_status,'active')='active'
      and coalesce(p.medical_grade,'junior')='junior'
      and (p_promotion is null or p.promotion_number=p_promotion)
    group by p.id,p.prenom,p.nom,p.promotion_number
  ), ranked as(
    select dense_rank() over(order by s.correct_count desc,s.accuracy_pct desc,s.answered_count desc,s.uid)::bigint rnk,s.* from scores s
  )
  select r.rnk,r.uid,r.display_name,r.promotion_number,r.correct_count,r.answered_count,r.accuracy_pct
  from ranked r order by r.rnk,r.display_name;
end;
$function$;

-- Les fonctions de progression Practice utilisent désormais chaque QCM répondu.
create or replace function public.practice_summary(
  p_scope text default 'month'::text,
  p_guard_id text default null::text
)
returns table(
  patients bigint,waiting bigint,discharged bigint,hospitalized bigint,
  specialist_opinions bigint,prescriptions bigint,complete_observations bigint,
  guards_count bigint,average_per_guard numeric,best_guard bigint,xp bigint,streak integer
)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  uid uuid:=auth.uid(); start_date date; end_date date;
  local_today date:=(now() at time zone 'Africa/Casablanca')::date;
  qcm_xp bigint:=0;
begin
  if uid is null then raise exception 'Authentification requise.'; end if;
  if p_scope not in ('guard','month','year','all') then raise exception 'Scope Practice invalide.'; end if;
  if p_scope='guard' and p_guard_id is null then raise exception 'guard_id requis.'; end if;
  if p_scope='month' then start_date:=date_trunc('month',local_today)::date; end_date:=(date_trunc('month',local_today)+interval '1 month')::date;
  elsif p_scope='year' then start_date:=date_trunc('year',local_today)::date; end_date:=(date_trunc('year',local_today)+interval '1 year')::date; end if;

  if p_scope<>'guard' then
    select coalesce(count(*)*2 + count(*) filter(where a.is_correct)*3,0)::bigint into qcm_xp
    from public.clinical_case_qcm_answers a
    where a.user_id=uid and (
      p_scope not in ('month','year') or (
        (a.answered_at at time zone 'Africa/Casablanca')::date>=start_date and
        (a.answered_at at time zone 'Africa/Casablanca')::date<end_date
      )
    );
  end if;

  return query with base as(
    select pc.* from public.practice_cases pc
    where pc.user_id=uid and pc.is_draft=false and public.practice_case_is_valid(pc)
      and (p_scope<>'guard' or pc.guard_id=p_guard_id)
      and (p_scope not in ('month','year') or (pc.guard_date>=start_date and pc.guard_date<end_date))
  ), per_guard as(select guard_id,count(*)::bigint n from base group by guard_id)
  select count(*)::bigint,
    count(*) filter(where b.waiting)::bigint,
    count(*) filter(where b.discharged)::bigint,
    count(*) filter(where b.hospitalized)::bigint,
    count(*) filter(where b.specialist_opinion_requested)::bigint,
    count(*) filter(where b.prescription_done)::bigint,
    count(*) filter(where public.practice_case_is_complete(b))::bigint,
    (select count(*)::bigint from per_guard),
    coalesce((select round(avg(n)::numeric,1) from per_guard),0),
    coalesce((select max(n) from per_guard),0)::bigint,
    coalesce(sum(public.practice_case_xp(b)),0)::bigint+qcm_xp,
    public.practice_current_streak(uid)
  from base b;
end;
$function$;

create or replace function public.practice_leaderboard(
  p_period text default 'month'::text,
  p_promotion smallint default null::smallint
)
returns table(rank bigint,user_id uuid,display_name text,promotion_number smallint,hospital text,xp bigint,case_count bigint)
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare start_date date; end_date date; local_today date:=(now() at time zone 'Africa/Casablanca')::date;
begin
  if auth.uid() is null then raise exception 'Authentification requise.'; end if;
  if p_period not in ('month','year') then raise exception 'Période Practice invalide.'; end if;
  if p_period='month' then start_date:=date_trunc('month',local_today)::date; end_date:=(date_trunc('month',local_today)+interval '1 month')::date;
  else start_date:=date_trunc('year',local_today)::date; end_date:=(date_trunc('year',local_today)+interval '1 year')::date; end if;
  return query with clinical as(
    select pc.user_id,coalesce(sum(public.practice_case_xp(pc)),0)::bigint clinical_xp,count(pc.id)::bigint cases
    from public.practice_cases pc
    where pc.is_draft=false and public.practice_case_is_valid(pc) and pc.guard_date>=start_date and pc.guard_date<end_date
    group by pc.user_id
  ), qcm as(
    select a.user_id,(count(*)*2+count(*) filter(where a.is_correct)*3)::bigint qcm_xp,count(*)::bigint qcms
    from public.clinical_case_qcm_answers a
    where (a.answered_at at time zone 'Africa/Casablanca')::date>=start_date
      and (a.answered_at at time zone 'Africa/Casablanca')::date<end_date
    group by a.user_id
  ), scores as(
    select p.id uid,trim(concat_ws(' ','Dr',nullif(p.prenom,''),nullif(p.nom,''))) display_name,p.promotion_number,p.hospital,
      (coalesce(c.clinical_xp,0)+coalesce(q.qcm_xp,0))::bigint score,
      coalesce(c.cases,0)::bigint cases,coalesce(q.qcms,0)::bigint qcms
    from public.profiles p
    left join public.practice_preferences pref on pref.user_id=p.id
    left join clinical c on c.user_id=p.id
    left join qcm q on q.user_id=p.id
    where coalesce(pref.leaderboard_opt_in,true)
      and coalesce(p.account_status,'active')='active'
      and coalesce(p.medical_grade,'junior')='junior'
      and (p_promotion is null or p.promotion_number=p_promotion)
      and (coalesce(c.cases,0)>0 or coalesce(q.qcms,0)>0)
  )
  select dense_rank() over(order by s.score desc,s.cases desc,s.qcms desc,s.uid)::bigint,
    s.uid,s.display_name,s.promotion_number,s.hospital,s.score,s.cases
  from scores s order by 1,s.display_name;
end;
$function$;

create or replace function public.practice_refresh_my_achievements()
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  uid uuid:=auth.uid(); a record; progress_value integer;
  total_patients integer; total_complete integer; total_specialist integer; total_guards integer;
  current_streak integer; qcm_answered integer; qcm_correct integer; clinical_xp integer; combined_xp integer;
begin
  if uid is null then raise exception 'Authentification requise.'; end if;
  select count(*)::int,
    count(*) filter(where public.practice_case_is_complete(pc))::int,
    count(*) filter(where pc.specialist_opinion_requested)::int,
    count(distinct pc.guard_id)::int,
    coalesce(sum(public.practice_case_xp(pc)),0)::int
  into total_patients,total_complete,total_specialist,total_guards,clinical_xp
  from public.practice_cases pc
  where pc.user_id=uid and pc.is_draft=false and public.practice_case_is_valid(pc);

  select count(*)::int,count(*) filter(where qa.is_correct)::int
  into qcm_answered,qcm_correct
  from public.clinical_case_qcm_answers qa where qa.user_id=uid;

  current_streak:=public.practice_current_streak(uid);
  combined_xp:=clinical_xp+qcm_answered*2+qcm_correct*3;

  for a in select * from public.practice_achievements loop
    progress_value:=case a.metric
      when 'patients' then total_patients when 'complete' then total_complete
      when 'specialist' then total_specialist when 'guards' then total_guards
      when 'streak' then current_streak when 'qcm_answered' then qcm_answered
      when 'qcm_correct' then qcm_correct when 'xp' then combined_xp else 0 end;
    insert into public.user_practice_achievements(user_id,achievement_id,progress,unlocked_at,updated_at)
    values(uid,a.id,progress_value,case when progress_value>=a.threshold then now() else null end,now())
    on conflict(user_id,achievement_id) do update set
      progress=excluded.progress,
      unlocked_at=coalesce(public.user_practice_achievements.unlocked_at,excluded.unlocked_at),
      updated_at=now();
  end loop;
end;
$function$;

commit;
