-- GardeFlow V11.6.52 — règles disciplinaires serveur par nom + PDF

create table if not exists public.official_disciplinary_name_rules (
  id uuid primary key default gen_random_uuid(),
  resource_id uuid not null references public.shared_resources(id) on delete cascade,
  resource_updated_at timestamptz not null,
  date_str date not null,
  shift_id text not null check (shift_id in ('urg-jour','urg-nuit','urg-24h')),
  red_text text not null,
  normalized_red_text text not null,
  detected_at timestamptz not null default now(),
  unique(resource_id, resource_updated_at, date_str, shift_id, normalized_red_text)
);

create index if not exists official_disciplinary_name_rules_date_idx
  on public.official_disciplinary_name_rules(date_str, resource_id, resource_updated_at);

alter table public.official_disciplinary_name_rules enable row level security;
revoke all on table public.official_disciplinary_name_rules from public, anon, authenticated;

create or replace function public.normalize_doctor_text(p_input text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  s text;
begin
  s := lower(coalesce(p_input,''));
  s := translate(
    s,
    'àáâäãåçèéêëìíîïñòóôöõùúûüýÿ',
    'aaaaaaceeeeiiiinooooouuuuyy'
  );
  s := replace(replace(replace(replace(s, '’', ' '), '''', ' '), '-', ' '), '—', ' ');
  s := regexp_replace(s, '(^|[[:space:]])(dr|docteur)([[:space:]]|$)', ' ', 'g');
  s := regexp_replace(s, '[^a-z0-9 ]+', ' ', 'g');
  s := regexp_replace(s, '[[:space:]]+', ' ', 'g');
  return trim(s);
end;
$$;

create or replace function public.profile_matches_disciplinary_rule(
  p_owner_id uuid,
  p_date date,
  p_rule_text text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  p public.profiles%rowtype;
  red_norm text;
  forward_name text;
  reverse_name text;
begin
  select * into p from public.profiles where id=p_owner_id;
  if not found then return false; end if;

  red_norm := public.normalize_doctor_text(p_rule_text);
  forward_name := public.normalize_doctor_text(coalesce(p.prenom,'') || ' ' || coalesce(p.nom,''));
  reverse_name := public.normalize_doctor_text(coalesce(p.nom,'') || ' ' || coalesce(p.prenom,''));

  if red_norm = '' then return false; end if;

  return (' ' || red_norm || ' ') like ('% ' || forward_name || ' %')
      or (' ' || red_norm || ' ') like ('% ' || reverse_name || ' %');
end;
$$;

revoke all on function public.profile_matches_disciplinary_rule(uuid,date,text)
  from public, anon, authenticated;

create or replace function public.current_disciplinary_rule_shift(
  p_owner_id uuid,
  p_date date
)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select r.shift_id
  from public.official_disciplinary_name_rules r
  join public.shared_resources sr
    on sr.id = r.resource_id
   and sr.kind = 'official_pdf'
   and sr.updated_at = r.resource_updated_at
  where r.date_str = p_date
    and public.profile_matches_disciplinary_rule(
      p_owner_id,
      p_date,
      r.normalized_red_text
    )
  order by r.detected_at desc
  limit 1;
$$;

revoke all on function public.current_disciplinary_rule_shift(uuid,date)
  from public, anon, authenticated;

create or replace function public.is_current_disciplinary_guard(
  p_owner_id uuid,
  p_date date
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    exists(
      select 1
      from public.official_disciplinary_guards d
      join public.shared_resources r
        on r.id = d.resource_id
       and r.kind = 'official_pdf'
       and r.updated_at = d.resource_updated_at
      where d.owner_id = p_owner_id
        and d.date_str = p_date
    )
    or public.current_disciplinary_rule_shift(p_owner_id,p_date) is not null;
$$;

revoke all on function public.is_current_disciplinary_guard(uuid,date)
  from public, anon, authenticated;

create or replace function public.register_official_disciplinary_marks(
  p_resource_id uuid,
  p_resource_updated_at timestamptz,
  p_marks jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  resource_row public.shared_resources%rowtype;
  mark jsonb;
  mark_date date;
  mark_shift text;
  mark_text text;
  mark_norm text;
  matched_count int := 0;
  rule_count int := 0;
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;

  select * into resource_row
  from public.shared_resources
  where id=p_resource_id and kind='official_pdf'
  for update;

  if not found then raise exception 'Planning officiel introuvable'; end if;
  if resource_row.updated_at is distinct from p_resource_updated_at then
    raise exception 'Le PDF a été remplacé pendant son analyse.';
  end if;

  delete from public.official_disciplinary_name_rules
  where resource_id=p_resource_id
    and resource_updated_at=p_resource_updated_at;

  for mark in
    select value
    from jsonb_array_elements(coalesce(p_marks,'[]'::jsonb))
  loop
    begin
      mark_date := nullif(mark->>'date','')::date;
      mark_shift := mark->>'shift_id';
      mark_text := trim(coalesce(mark->>'red_text',''));
      mark_norm := public.normalize_doctor_text(mark_text);
    exception when others then
      continue;
    end;

    if mark_date is null
       or mark_shift not in ('urg-jour','urg-nuit','urg-24h')
       or mark_norm = '' then
      continue;
    end if;

    insert into public.official_disciplinary_name_rules(
      resource_id,resource_updated_at,date_str,shift_id,
      red_text,normalized_red_text,detected_at
    )
    values(
      p_resource_id,p_resource_updated_at,mark_date,mark_shift,
      mark_text,mark_norm,now()
    )
    on conflict(resource_id,resource_updated_at,date_str,shift_id,normalized_red_text)
    do update set red_text=excluded.red_text, detected_at=now();

    rule_count := rule_count + 1;
  end loop;

  perform set_config('gardeflow.official_import','1',true);

  with matches as (
    select
      p.id as owner_id,
      r.date_str,
      r.shift_id,
      r.resource_id,
      r.resource_updated_at
    from public.profiles p
    join public.official_disciplinary_name_rules r
      on r.resource_id=p_resource_id
     and r.resource_updated_at=p_resource_updated_at
    where p.account_status='active'
      and public.profile_matches_disciplinary_rule(p.id,r.date_str,r.normalized_red_text)
  )
  insert into public.official_disciplinary_guards(
    owner_id,date_str,shift_id,resource_id,resource_updated_at,detected_at
  )
  select owner_id,date_str,shift_id,resource_id,resource_updated_at,now()
  from matches
  on conflict(owner_id,date_str,resource_id,resource_updated_at)
  do update set shift_id=excluded.shift_id, detected_at=now();

  with matches as (
    select
      p.id as owner_id,
      r.date_str,
      r.shift_id,
      r.resource_id,
      r.resource_updated_at
    from public.profiles p
    join public.official_disciplinary_name_rules r
      on r.resource_id=p_resource_id
     and r.resource_updated_at=p_resource_updated_at
    where p.account_status='active'
      and public.profile_matches_disciplinary_rule(p.id,r.date_str,r.normalized_red_text)
  )
  update public.planning_entries e
  set is_disciplinary=true,
      shift_id=m.shift_id,
      source_type='official_emergency',
      source_resource_id=m.resource_id,
      source_resource_updated_at=m.resource_updated_at
  from matches m
  where e.owner_id=m.owner_id
    and e.date_str=m.date_str
    and e.deleted_at is null;

  get diagnostics matched_count = row_count;

  update public.official_roster_import_runs
  set sync_revision='v11.6.52-r1',
      imported_at=now(),
      imported_by=auth.uid()
  where resource_id=p_resource_id
    and resource_updated_at=p_resource_updated_at;

  return jsonb_build_object(
    'rules',rule_count,
    'active_entries_locked',matched_count,
    'revision','v11.6.52-r1'
  );
end;
$$;

grant execute on function public.register_official_disciplinary_marks(uuid,timestamptz,jsonb)
  to authenticated;

drop trigger if exists protect_disciplinary_guard_trigger on public.planning_entries;
create trigger protect_disciplinary_guard_trigger
before insert or update or delete on public.planning_entries
for each row execute function public.protect_disciplinary_guard();

insert into public.official_disciplinary_name_rules(
  resource_id,resource_updated_at,date_str,shift_id,red_text,normalized_red_text
)
select
  r.id,r.updated_at,v.date_str,v.shift_id,v.red_text,
  public.normalize_doctor_text(v.red_text)
from public.shared_resources r
cross join (values
  (date '2026-08-25','urg-24h','Lahroussi Aymen'),
  (date '2026-08-29','urg-24h','Khadraoui Nour Abbassi Amine'),
  (date '2026-09-05','urg-24h','Driouech Salma'),
  (date '2026-09-19','urg-24h','Bakertit Hiba'),
  (date '2026-09-26','urg-24h','Douni Driss')
) as v(date_str,shift_id,red_text)
where r.kind='official_pdf' and r.slot='hm6_bouskoura'
on conflict(resource_id,resource_updated_at,date_str,shift_id,normalized_red_text)
do update set red_text=excluded.red_text, detected_at=now();

insert into public.official_disciplinary_name_rules(
  resource_id,resource_updated_at,date_str,shift_id,red_text,normalized_red_text
)
select
  r.id,r.updated_at,v.date_str,v.shift_id,v.red_text,
  public.normalize_doctor_text(v.red_text)
from public.shared_resources r
cross join (values
  (date '2026-08-29','urg-24h','EL FERDAOUS Abderrahmane'),
  (date '2026-09-12','urg-24h','AMCHAAROU HAMZA')
) as v(date_str,shift_id,red_text)
where r.kind='official_pdf' and r.slot='hm6_rabat'
on conflict(resource_id,resource_updated_at,date_str,shift_id,normalized_red_text)
do update set red_text=excluded.red_text, detected_at=now();

insert into public.official_disciplinary_name_rules(
  resource_id,resource_updated_at,date_str,shift_id,red_text,normalized_red_text
)
select
  r.id,r.updated_at,date '2026-09-12','urg-24h','YOUSSEFI Yasmine',
  public.normalize_doctor_text('YOUSSEFI Yasmine')
from public.shared_resources r
where r.kind='official_pdf' and r.slot='hck_casa'
on conflict(resource_id,resource_updated_at,date_str,shift_id,normalized_red_text)
do update set red_text=excluded.red_text, detected_at=now();

select set_config('gardeflow.official_import','1',true);

insert into public.official_disciplinary_guards(
  owner_id,date_str,shift_id,resource_id,resource_updated_at,detected_at
)
select
  p.id,r.date_str,r.shift_id,r.resource_id,r.resource_updated_at,now()
from public.profiles p
join public.official_disciplinary_name_rules r
  on public.profile_matches_disciplinary_rule(p.id,r.date_str,r.normalized_red_text)
join public.shared_resources sr
  on sr.id=r.resource_id
 and sr.updated_at=r.resource_updated_at
 and sr.kind='official_pdf'
where p.account_status='active'
on conflict(owner_id,date_str,resource_id,resource_updated_at)
do update set shift_id=excluded.shift_id, detected_at=now();

with matches as (
  select
    p.id owner_id,r.date_str,r.shift_id,r.resource_id,r.resource_updated_at
  from public.profiles p
  join public.official_disciplinary_name_rules r
    on public.profile_matches_disciplinary_rule(p.id,r.date_str,r.normalized_red_text)
  join public.shared_resources sr
    on sr.id=r.resource_id
   and sr.updated_at=r.resource_updated_at
   and sr.kind='official_pdf'
  where p.account_status='active'
)
update public.planning_entries e
set is_disciplinary=true,
    shift_id=m.shift_id,
    source_type='official_emergency',
    source_resource_id=m.resource_id,
    source_resource_updated_at=m.resource_updated_at
from matches m
where e.owner_id=m.owner_id
  and e.date_str=m.date_str
  and e.deleted_at is null;

update public.official_roster_import_runs ir
set sync_revision='v11.6.52-r1'
where exists(
  select 1 from public.shared_resources r
  where r.id=ir.resource_id
    and r.updated_at=ir.resource_updated_at
    and r.kind='official_pdf'
);

create or replace function public.official_roster_import_is_current(
  p_resource_id uuid,
  p_resource_updated_at timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Réservé à l’administrateur'; end if;
  return exists(
    select 1 from public.official_roster_import_runs r
    where r.resource_id=p_resource_id
      and r.resource_updated_at=p_resource_updated_at
      and r.sync_revision='v11.6.52-r1'
  );
end;
$$;
