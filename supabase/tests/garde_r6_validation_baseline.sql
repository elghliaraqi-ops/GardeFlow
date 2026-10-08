-- Disposable PostgreSQL baseline used only by Garde R6 CI.
-- It recreates the production interfaces consumed by the R6 migration
-- without copying any production data.

create extension if not exists pgcrypto;

do $$
begin
  if not exists (select 1 from pg_roles where rolname='anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then
    create role service_role nologin;
  end if;
end
$$;

create schema if not exists auth;

create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid
$$;

grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;

create table public.profiles (
  id uuid primary key,
  phone text not null unique,
  nom text not null,
  prenom text not null,
  service text not null default 'Test',
  fonction text not null default 'junior',
  hospital text not null,
  role text not null default 'medecin',
  created_at timestamptz not null default now(),
  medical_grade text not null default 'junior',
  account_status text not null default 'active',
  promotion_number smallint,
  avatar_key text,
  appearance_theme text not null default 'black'
);

create table public.shared_resources (
  id uuid primary key default gen_random_uuid(),
  kind text not null,
  slot text,
  storage_path text not null,
  display_name text not null,
  mime_type text not null,
  uploaded_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  hospital text
);

create table public.planning_entries (
  id text primary key,
  date_str date not null,
  shift_id text not null,
  owner_phone text not null,
  owner_name text not null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  owner_id uuid not null,
  leave_request_id text,
  source_type text,
  source_resource_id uuid,
  source_resource_updated_at timestamptz,
  is_disciplinary boolean not null default false,
  disciplinary_reason text
);

create unique index planning_entries_active_owner_date_uidx
  on public.planning_entries(owner_id,date_str)
  where deleted_at is null;

create table public.planning_months (
  owner_id uuid not null,
  year integer not null,
  month integer not null,
  status text not null default 'draft',
  submitted_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid,
  rejection_reason text,
  updated_at timestamptz not null default now(),
  auto_validation_blocked boolean not null default false,
  approval_source text,
  primary key(owner_id,year,month)
);

create table public.audit_log (
  id bigserial primary key,
  actor_id uuid,
  actor_name text not null,
  action text not null,
  entity_type text not null,
  entity_id text not null,
  subject_id uuid,
  subject_name text,
  reason text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.official_roster_profile_sync (
  resource_id uuid not null,
  resource_updated_at timestamptz not null,
  profile_id uuid not null,
  profile_signature text not null default '',
  sync_revision text not null default 'v11.6.5-r1',
  synced_at timestamptz not null default now(),
  assignment_count integer not null default 0,
  inserted_count integer not null default 0,
  updated_count integer not null default 0,
  removed_count integer not null default 0,
  skipped_manual_count integer not null default 0,
  skipped_locked_count integer not null default 0,
  invalid_count integer not null default 0,
  unmatched_cells jsonb not null default '[]'::jsonb,
  primary key(resource_id,resource_updated_at,profile_id)
);

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select role='admin' and account_status='active'
    from public.profiles
    where id=auth.uid()
  ),false)
$$;

create or replace function public.guardeflow_roster_revision_rank(p_revision text)
returns integer
language sql
immutable
set search_path = public
as $$
  select coalesce(
    nullif((regexp_match(coalesce(p_revision,''), 'r([0-9]+)$'))[1], '')::int,
    0
  )
$$;

create or replace function public.guardeflow_is_past_month(p_date date)
returns boolean
language sql
stable
set search_path = public
as $$
  select date_trunc('month', p_date)::date
       < date_trunc('month', current_date)::date
$$;

create or replace function public.import_official_emergency_roster_for_profile_v2(
  p_resource_id uuid,
  p_resource_updated_at timestamptz,
  p_profile_id uuid,
  p_assignments jsonb,
  p_parser_revision text,
  p_unmatched_cells jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  d date;
  s text;
  disc boolean;
  existing_id text;
  ins integer := 0;
  upd integer := 0;
  rem integer := 0;
begin
  if auth.uid() is null then raise exception 'Session requise'; end if;
  if p_profile_id <> auth.uid() and not public.is_admin() then
    raise exception 'Accès refusé';
  end if;

  if public.guardeflow_roster_revision_rank(p_parser_revision) < 4 then
    raise exception 'Parseur officiel obsolète';
  end if;

  for item in
    select value from jsonb_array_elements(coalesce(p_assignments,'[]'::jsonb))
  loop
    if nullif(item->>'profile_id','')::uuid <> p_profile_id then
      continue;
    end if;

    d := nullif(item->>'date','')::date;
    s := item->>'shift_id';
    disc := coalesce(nullif(item->>'is_disciplinary','')::boolean,false);

    if d is null or s not in ('urg-jour','urg-nuit','urg-24h') then
      continue;
    end if;

    select id into existing_id
    from public.planning_entries
    where owner_id=p_profile_id
      and date_str=d
      and deleted_at is null
    limit 1;

    if existing_id is null then
      insert into public.planning_entries(
        id,date_str,shift_id,owner_phone,owner_name,owner_id,
        source_type,source_resource_id,source_resource_updated_at,is_disciplinary
      )
      select
        'r6test-'||p_profile_id::text||'-'||d::text,
        d,s,p.phone,trim(p.prenom||' '||p.nom),p.id,
        'official_emergency',p_resource_id,p_resource_updated_at,disc
      from public.profiles p where p.id=p_profile_id;
      ins := ins + 1;
    else
      update public.planning_entries
      set shift_id=s,
          source_type='official_emergency',
          source_resource_id=p_resource_id,
          source_resource_updated_at=p_resource_updated_at,
          is_disciplinary=disc
      where id=existing_id
        and source_type='official_emergency';
      if found then upd := upd + 1; end if;
    end if;
  end loop;

  update public.planning_entries e
  set deleted_at=now()
  where e.owner_id=p_profile_id
    and e.source_type='official_emergency'
    and e.source_resource_id=p_resource_id
    and e.deleted_at is null
    and not exists (
      select 1
      from jsonb_array_elements(coalesce(p_assignments,'[]'::jsonb)) x
      where nullif(x->>'profile_id','')::uuid=p_profile_id
        and nullif(x->>'date','')::date=e.date_str
    );
  get diagnostics rem = row_count;

  insert into public.official_roster_profile_sync(
    resource_id,resource_updated_at,profile_id,profile_signature,sync_revision,
    assignment_count,inserted_count,updated_count,removed_count,unmatched_cells
  ) values (
    p_resource_id,p_resource_updated_at,p_profile_id,'synthetic',p_parser_revision,
    jsonb_array_length(coalesce(p_assignments,'[]'::jsonb)),ins,upd,rem,
    coalesce(p_unmatched_cells,'[]'::jsonb)
  )
  on conflict(resource_id,resource_updated_at,profile_id) do update
  set sync_revision=excluded.sync_revision,
      synced_at=now(),
      assignment_count=excluded.assignment_count,
      inserted_count=excluded.inserted_count,
      updated_count=excluded.updated_count,
      removed_count=excluded.removed_count,
      unmatched_cells=excluded.unmatched_cells;

  return jsonb_build_object(
    'inserted',ins,'updated',upd,'removed',rem,'parser_revision',p_parser_revision
  );
end
$$;

grant usage on schema public to anon, authenticated, service_role;
grant select,insert,update,delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;
