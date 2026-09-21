-- HUIM6 Planning V9.1 - Supabase/PostgreSQL
-- À exécuter une seule fois dans Supabase > SQL Editor.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  phone text not null unique,
  nom text not null,
  prenom text not null,
  service text not null,
  fonction text not null check (fonction in ('junior','senior','admin')),
  hospital text not null,
  role text not null default 'medecin' check (role in ('medecin','admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.planning_entries (
  id text primary key,
  date_str text not null,
  shift_id text not null,
  owner_phone text not null references public.profiles(phone) on update cascade,
  owner_name text not null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.exchange_requests (
  id text primary key,
  type text not null check (type in ('transfer','exchange')),
  planning_entry_id text not null references public.planning_entries(id),
  date_str text not null,
  shift_id text not null,
  target_planning_entry_id text references public.planning_entries(id),
  target_date_str text,
  target_shift_id text,
  from_phone text not null references public.profiles(phone),
  from_name text not null,
  to_phone text not null references public.profiles(phone),
  to_name text not null,
  status text not null default 'pendingB' check (status in ('pendingB','pendingAdmin','approved','declinedB','rejectedAdmin','cancelled')),
  created_at timestamptz not null default now(),
  check (from_phone <> to_phone),
  check ((type='transfer' and target_planning_entry_id is null) or
         (type='exchange' and target_planning_entry_id is not null))
);

create index if not exists planning_owner_date_idx on public.planning_entries(owner_phone,date_str);
create unique index if not exists planning_owner_date_active_uidx
  on public.planning_entries(owner_phone,date_str) where deleted_at is null;
create index if not exists exchange_from_idx on public.exchange_requests(from_phone,status);
create index if not exists exchange_to_idx on public.exchange_requests(to_phone,status);

-- Création automatique du profil à l'inscription Supabase Auth.
-- V9.1 utilise Email/Password avec une adresse technique ; le vrai téléphone
-- est transmis dans raw_user_meta_data.phone.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles(id,phone,nom,prenom,service,fonction,hospital,role)
  values (
    new.id,
    coalesce(new.phone,new.raw_user_meta_data->>'phone'),
    coalesce(new.raw_user_meta_data->>'nom',''),
    coalesce(new.raw_user_meta_data->>'prenom',''),
    coalesce(new.raw_user_meta_data->>'service',''),
    coalesce(new.raw_user_meta_data->>'fonction','junior'),
    coalesce(new.raw_user_meta_data->>'hospital',''),
    'medecin'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.current_phone()
returns text language sql stable security definer set search_path=public
as $$ select phone from public.profiles where id=auth.uid() $$;

create or replace function public.current_hospital()
returns text language sql stable security definer set search_path=public
as $$ select hospital from public.profiles where id=auth.uid() $$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select coalesce((select role='admin' from public.profiles where id=auth.uid()),false) $$;


-- Suppression prioritaire par l'administrateur.
-- La garde est archivée (soft-delete) afin de conserver l'historique des
-- transferts/échanges qui la référencent. Toute demande encore active liée
-- à la garde est annulée avant l'archivage.
create or replace function public.admin_delete_planning(p_entry_id text)
returns void
language plpgsql
security definer set search_path=public
as $$
declare e public.planning_entries%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;

  select * into e
  from public.planning_entries
  where id=p_entry_id and deleted_at is null
  for update;

  if not found then
    raise exception 'Garde introuvable';
  end if;

  update public.exchange_requests
  set status='cancelled'
  where status in ('pendingB','pendingAdmin')
    and (planning_entry_id=p_entry_id or target_planning_entry_id=p_entry_id);

  update public.planning_entries
  set deleted_at=now()
  where id=p_entry_id;
end;
$$;

grant execute on function public.admin_delete_planning(text) to authenticated;

alter table public.profiles enable row level security;
alter table public.planning_entries enable row level security;
alter table public.exchange_requests enable row level security;

-- Profils visibles uniquement dans le même établissement, sauf admin réseau.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated using (
  id=auth.uid() or public.is_admin() or hospital=public.current_hospital()
);

drop policy if exists planning_select on public.planning_entries;
create policy planning_select on public.planning_entries for select to authenticated using (
  public.is_admin() or exists(
    select 1 from public.profiles p
    where p.phone=planning_entries.owner_phone and p.hospital=public.current_hospital()
  )
);

drop policy if exists planning_insert on public.planning_entries;
create policy planning_insert on public.planning_entries for insert to authenticated with check (
  owner_phone=public.current_phone()
);

drop policy if exists planning_update on public.planning_entries;
create policy planning_update on public.planning_entries for update to authenticated using (
  owner_phone=public.current_phone()
) with check (owner_phone=public.current_phone());

drop policy if exists planning_delete on public.planning_entries;
create policy planning_delete on public.planning_entries for delete to authenticated using (
  owner_phone=public.current_phone()
);

drop policy if exists exchange_select on public.exchange_requests;
create policy exchange_select on public.exchange_requests for select to authenticated using (
  public.is_admin() or from_phone=public.current_phone() or to_phone=public.current_phone()
);

drop policy if exists exchange_insert on public.exchange_requests;
create policy exchange_insert on public.exchange_requests for insert to authenticated with check (
  from_phone=public.current_phone()
  and exists(
    select 1 from public.profiles a, public.profiles b
    where a.phone=exchange_requests.from_phone and b.phone=exchange_requests.to_phone and a.hospital=b.hospital
  )
  and exists(
    select 1 from public.planning_entries s
    where s.id=exchange_requests.planning_entry_id and s.owner_phone=exchange_requests.from_phone
  )
  and (
    type='transfer' or exists(
      select 1 from public.planning_entries t
      where t.id=exchange_requests.target_planning_entry_id and t.owner_phone=exchange_requests.to_phone
    )
  )
);

-- Pas d'UPDATE direct : les transitions passent par les RPC ci-dessous.

-- Une garde engagée dans une demande active ne peut pas être modifiée/supprimée
-- hors de la transaction d'approbation administrateur.
create or replace function public.protect_locked_planning()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if current_setting('huim6.review_request',true)='1' then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;
  if exists(
    select 1 from public.exchange_requests r
    where r.status in ('pendingB','pendingAdmin')
      and (r.planning_entry_id=old.id or r.target_planning_entry_id=old.id)
  ) then
    raise exception 'Cette garde est verrouillée par une demande active';
  end if;
  if tg_op='DELETE' then return old; else return new; end if;
end;
$$;

drop trigger if exists protect_locked_planning_trigger on public.planning_entries;
create trigger protect_locked_planning_trigger
before update or delete on public.planning_entries
for each row execute procedure public.protect_locked_planning();

create or replace function public.respond_shift_request(p_request_id text,p_action text)
returns void
language plpgsql
security definer set search_path=public
as $$
declare r public.exchange_requests%rowtype;
begin
  select * into r from public.exchange_requests where id=p_request_id for update;
  if not found then raise exception 'Demande introuvable'; end if;
  if r.to_phone<>public.current_phone() then raise exception 'Non autorisé'; end if;
  if r.status<>'pendingB' then raise exception 'Demande déjà traitée'; end if;
  if p_action='accept' then
    update public.exchange_requests set status='pendingAdmin' where id=p_request_id;
  elsif p_action='decline' then
    update public.exchange_requests set status='declinedB' where id=p_request_id;
  else raise exception 'Action invalide';
  end if;
end;
$$;

create or replace function public.cancel_shift_request(p_request_id text)
returns void
language plpgsql
security definer set search_path=public
as $$
declare r public.exchange_requests%rowtype;
begin
  select * into r from public.exchange_requests where id=p_request_id for update;
  if not found then raise exception 'Demande introuvable'; end if;
  if r.from_phone<>public.current_phone() or r.status<>'pendingB' then raise exception 'Non autorisé'; end if;
  update public.exchange_requests set status='cancelled' where id=p_request_id;
end;
$$;

create or replace function public.review_shift_request(p_request_id text,p_action text)
returns void
language plpgsql
security definer set search_path=public
as $$
declare
  r public.exchange_requests%rowtype;
  source public.planning_entries%rowtype;
  target public.planning_entries%rowtype;
  from_hospital text;
  to_hospital text;
begin
  if not public.is_admin() then raise exception 'Réservé à l’administrateur'; end if;
  select * into r from public.exchange_requests where id=p_request_id for update;
  if not found then raise exception 'Demande introuvable'; end if;
  if r.status<>'pendingAdmin' then raise exception 'Demande non prête pour validation'; end if;
  if p_action='reject' then
    update public.exchange_requests set status='rejectedAdmin' where id=p_request_id;
    return;
  elsif p_action<>'approve' then raise exception 'Action invalide';
  end if;

  perform set_config('huim6.review_request','1',true);

  select hospital into from_hospital from public.profiles where phone=r.from_phone;
  select hospital into to_hospital from public.profiles where phone=r.to_phone;
  if from_hospital is distinct from to_hospital then
    raise exception 'Transfert/échange inter-établissements interdit';
  end if;

  select * into source from public.planning_entries where id=r.planning_entry_id for update;
  if not found or source.owner_phone<>r.from_phone then raise exception 'Garde source modifiée'; end if;

  if r.type='transfer' then
    if exists(select 1 from public.planning_entries where owner_phone=r.to_phone and date_str=source.date_str) then
      raise exception 'Le destinataire a déjà une garde ce jour-là';
    end if;
    update public.planning_entries
      set owner_phone=r.to_phone, owner_name=r.to_name
      where id=source.id;
  else
    select * into target from public.planning_entries where id=r.target_planning_entry_id for update;
    if not found or target.owner_phone<>r.to_phone then raise exception 'Garde cible modifiée'; end if;
    if source.date_str=target.date_str then
      -- Même jour : chaque médecin garde sa ligne/date et reçoit le type de
      -- garde de l'autre. Cela respecte unique(owner_phone, date_str).
      update public.planning_entries set shift_id=target.shift_id where id=source.id;
      update public.planning_entries set shift_id=source.shift_id where id=target.id;
    else
      if exists(select 1 from public.planning_entries where owner_phone=r.to_phone and date_str=source.date_str and deleted_at is null and id<>target.id) then
        raise exception 'Conflit de planning du destinataire';
      end if;
      if exists(select 1 from public.planning_entries where owner_phone=r.from_phone and date_str=target.date_str and deleted_at is null and id<>source.id) then
        raise exception 'Conflit de planning du demandeur';
      end if;
      -- Dates différentes : chaque médecin conserve sa ligne/propriétaire et
      -- reçoit la date + le type de garde de l'autre.
      update public.planning_entries
        set date_str=target.date_str, shift_id=target.shift_id
        where id=source.id;
      update public.planning_entries
        set date_str=source.date_str, shift_id=source.shift_id
        where id=target.id;
    end if;
  end if;
  update public.exchange_requests set status='approved' where id=p_request_id;
end;
$$;

grant select on public.profiles, public.planning_entries, public.exchange_requests to authenticated;
grant insert,update,delete on public.planning_entries to authenticated;
grant insert on public.exchange_requests to authenticated;
grant execute on function public.respond_shift_request(text,text) to authenticated;
grant execute on function public.cancel_shift_request(text) to authenticated;
grant execute on function public.review_shift_request(text,text) to authenticated;

-- Realtime : activer les deux tables métier dans la publication Supabase.
do $$ begin
  alter publication supabase_realtime add table public.planning_entries;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.exchange_requests;
exception when duplicate_object then null; end $$;
-- HUIM6 Planning V9.7
-- Patch cumulatif à exécuter UNE FOIS après une installation V9.5.
-- Il inclut la suppression admin V9.6 + le circuit d'approbation des congés V9.7.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- 1) Suppression / archivage admin des gardes et congés approuvés
-- ---------------------------------------------------------------------------
alter table public.planning_entries
  add column if not exists deleted_at timestamptz;

alter table public.planning_entries
  drop constraint if exists planning_entries_owner_phone_date_str_key;

drop index if exists public.planning_owner_date_active_uidx;
create unique index planning_owner_date_active_uidx
  on public.planning_entries(owner_phone,date_str)
  where deleted_at is null;

-- ---------------------------------------------------------------------------
-- 2) Demandes de congé
-- ---------------------------------------------------------------------------
create table if not exists public.leave_requests (
  id text primary key,
  date_str text not null,
  owner_phone text not null references public.profiles(phone) on update cascade,
  owner_name text not null,
  status text not null default 'pendingAdmin'
    check (status in ('pendingAdmin','approved','rejectedAdmin','cancelled')),
  planning_entry_id text references public.planning_entries(id),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);

create index if not exists leave_owner_idx on public.leave_requests(owner_phone,status);
create unique index if not exists leave_pending_owner_date_uidx
  on public.leave_requests(owner_phone,date_str)
  where status='pendingAdmin';

alter table public.leave_requests enable row level security;

drop policy if exists leave_select on public.leave_requests;
create policy leave_select on public.leave_requests for select to authenticated using (
  public.is_admin() or owner_phone=public.current_phone()
);

drop policy if exists leave_insert on public.leave_requests;
create policy leave_insert on public.leave_requests for insert to authenticated with check (
  owner_phone=public.current_phone()
  and status='pendingAdmin'
  and planning_entry_id is null
);

-- Les changements d'état passent uniquement par RPC.
grant select, insert on public.leave_requests to authenticated;

create or replace function public.cancel_leave_request(p_request_id text)
returns void
language plpgsql
security definer set search_path=public
as $$
declare r public.leave_requests%rowtype;
begin
  select * into r from public.leave_requests where id=p_request_id for update;
  if not found then raise exception 'Demande de congé introuvable'; end if;
  if r.owner_phone<>public.current_phone() or r.status<>'pendingAdmin' then
    raise exception 'Annulation non autorisée';
  end if;
  update public.leave_requests
  set status='cancelled', reviewed_at=now()
  where id=p_request_id;
end;
$$;

create or replace function public.review_leave_request(p_request_id text,p_action text)
returns void
language plpgsql
security definer set search_path=public
as $$
declare
  r public.leave_requests%rowtype;
  new_entry_id text;
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;

  select * into r from public.leave_requests where id=p_request_id for update;
  if not found then raise exception 'Demande de congé introuvable'; end if;
  if r.status<>'pendingAdmin' then raise exception 'Demande déjà traitée'; end if;

  if p_action='reject' then
    update public.leave_requests
    set status='rejectedAdmin', reviewed_at=now()
    where id=p_request_id;
    return;
  elsif p_action<>'approve' then
    raise exception 'Action invalide';
  end if;

  if exists(
    select 1 from public.planning_entries
    where owner_phone=r.owner_phone and date_str=r.date_str and deleted_at is null
  ) then
    raise exception 'Une affectation existe déjà pour ce médecin ce jour-là';
  end if;

  new_entry_id := 'leave-' || replace(gen_random_uuid()::text,'-','');

  insert into public.planning_entries(id,date_str,shift_id,owner_phone,owner_name,created_at)
  values(new_entry_id,r.date_str,'conge',r.owner_phone,r.owner_name,now());

  update public.leave_requests
  set status='approved', planning_entry_id=new_entry_id, reviewed_at=now()
  where id=p_request_id;
end;
$$;

grant execute on function public.cancel_leave_request(text) to authenticated;
grant execute on function public.review_leave_request(text,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3) Suppression prioritaire admin de toute affectation, congés compris
-- ---------------------------------------------------------------------------
create or replace function public.admin_delete_planning(p_entry_id text)
returns void
language plpgsql
security definer set search_path=public
as $$
declare e public.planning_entries%rowtype;
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;

  select * into e
  from public.planning_entries
  where id=p_entry_id and deleted_at is null
  for update;

  if not found then
    raise exception 'Affectation introuvable';
  end if;

  update public.exchange_requests
  set status='cancelled'
  where status in ('pendingB','pendingAdmin')
    and (planning_entry_id=p_entry_id or target_planning_entry_id=p_entry_id);

  -- Si c'est un congé approuvé, son historique reste visible comme annulé
  -- après suppression administrative.
  if e.shift_id='conge' then
    update public.leave_requests
    set status='cancelled', reviewed_at=now()
    where planning_entry_id=p_entry_id and status='approved';
  end if;

  update public.planning_entries
  set deleted_at=now()
  where id=p_entry_id;
end;
$$;

grant execute on function public.admin_delete_planning(text) to authenticated;

-- Realtime pour les demandes de congé.
do $$ begin
  alter publication supabase_realtime add table public.leave_requests;
exception when duplicate_object then null; end $$;

-- V9.8 — Tokens FCM
create table if not exists public.push_tokens (
  token text primary key,
  owner_phone text not null references public.profiles(phone) on update cascade on delete cascade,
  platform text not null default 'web',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists push_tokens_owner_idx on public.push_tokens(owner_phone);
alter table public.push_tokens enable row level security;
revoke all on public.push_tokens from anon, authenticated;

create or replace function public.register_push_token(p_token text, p_platform text default 'web')
returns void language plpgsql security definer set search_path=public as $$
declare p text;
begin
  p := public.current_phone();
  if p is null then raise exception 'Session absente'; end if;
  if coalesce(trim(p_token),'')='' then raise exception 'Token push vide'; end if;
  insert into public.push_tokens(token,owner_phone,platform,updated_at)
  values (p_token,p,coalesce(nullif(trim(p_platform),''),'web'),now())
  on conflict (token) do update set owner_phone=excluded.owner_phone,platform=excluded.platform,updated_at=now();
end; $$;

create or replace function public.unregister_push_token(p_token text)
returns void language plpgsql security definer set search_path=public as $$
begin
  delete from public.push_tokens where token=p_token and owner_phone=public.current_phone();
end; $$;

grant execute on function public.register_push_token(text,text) to authenticated;
grant execute on function public.unregister_push_token(text) to authenticated;

-- FINAL OVERRIDES GARDEFLOW 11.1.5
-- GardeFlow 11.1.5
-- Règles d'échange consolidées :
-- 1) Tout échange est limité au même hôpital.
-- 2) Toute garde SERVICE impliquée dans l'échange impose le même service aux deux médecins.
-- 3) SERVICE <-> SERVICE (même service) : appliqué dès l'acceptation du destinataire, sans validation ADMIN.
-- 4) Tout échange impliquant URGENCES : validation ADMIN obligatoire.
-- Les transferts restent inchangés.

-- ---------------------------------------------------------------------------
-- RLS : verrouille les règles dès la création de la demande.
-- ---------------------------------------------------------------------------
drop policy if exists exchange_insert on public.exchange_requests;
create policy exchange_insert on public.exchange_requests
for insert to authenticated
with check (
  public.current_account_active()
  and from_id=auth.uid()
  and from_id<>to_id
  and status='pendingB'
  and exists(
    select 1
    from public.profiles a
    join public.profiles b on true
    where a.id=exchange_requests.from_id
      and b.id=exchange_requests.to_id
      and a.account_status='active'
      and b.account_status='active'
      and a.hospital=b.hospital
  )
  and exists(
    select 1
    from public.planning_entries s
    where s.id=exchange_requests.planning_entry_id
      and s.owner_id=exchange_requests.from_id
      and s.deleted_at is null
      and s.shift_id<>'conge'
      and s.date_str=exchange_requests.date_str
      and s.shift_id=exchange_requests.shift_id
      and not public.guard_has_started(s.date_str,s.shift_id)
  )
  and (
    type='transfer'
    or (
      type='exchange'
      and exists(
        select 1
        from public.planning_entries t
        where t.id=exchange_requests.target_planning_entry_id
          and t.owner_id=exchange_requests.to_id
          and t.deleted_at is null
          and t.shift_id<>'conge'
          and t.date_str=exchange_requests.target_date_str
          and t.shift_id=exchange_requests.target_shift_id
          and not public.guard_has_started(t.date_str,t.shift_id)
      )
      and (
        -- URGENCES <-> URGENCES : le même hôpital suffit.
        not (
          exchange_requests.shift_id like 'service-%'
          or exchange_requests.target_shift_id like 'service-%'
        )
        or exists(
          -- Dès qu'une garde SERVICE intervient, les deux médecins doivent
          -- appartenir au même service.
          select 1
          from public.profiles a
          join public.profiles b on true
          where a.id=exchange_requests.from_id
            and b.id=exchange_requests.to_id
            and nullif(trim(a.service),'') is not null
            and nullif(trim(b.service),'') is not null
            and trim(a.service)=trim(b.service)
        )
      )
    )
  )
);

-- ---------------------------------------------------------------------------
-- Acceptation par le médecin destinataire.
-- ---------------------------------------------------------------------------
create or replace function public.respond_shift_request(p_request_id text,p_action text)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  r public.exchange_requests%rowtype;
  source public.planning_entries%rowtype;
  target public.planning_entries%rowtype;
  from_hospital text;
  to_hospital text;
  from_service text;
  to_service text;
  auto_service_exchange boolean := false;
  involves_service boolean := false;
begin
  select * into r
  from public.exchange_requests
  where id=p_request_id
  for update;

  if not found then raise exception 'Demande introuvable'; end if;
  if r.to_id<>auth.uid() then raise exception 'Non autorisé'; end if;
  if r.status<>'pendingB' then raise exception 'Demande déjà traitée'; end if;
  if not public.current_account_active() then raise exception 'Compte actif requis'; end if;

  -- Un destinataire doit toujours pouvoir refuser une demande encore en attente,
  -- y compris une ancienne demande devenue invalide après cette migration.
  if p_action='decline' then
    update public.exchange_requests set status='declinedB' where id=p_request_id;
    perform public.write_audit('exchange.declined','exchange_request',p_request_id,r.to_id,r.to_name);
    return;
  elsif p_action<>'accept' then
    raise exception 'Action invalide';
  end if;

  select * into source
  from public.planning_entries
  where id=r.planning_entry_id and deleted_at is null
  for update;

  if not found
     or source.owner_id<>r.from_id
     or source.shift_id='conge'
     or source.date_str<>r.date_str
     or source.shift_id<>r.shift_id
     or public.guard_has_started(source.date_str,source.shift_id)
  then
    raise exception 'La garde source a été modifiée, supprimée ou a déjà commencé';
  end if;

  select hospital,service into from_hospital,from_service
  from public.profiles
  where id=r.from_id and account_status='active';

  select hospital,service into to_hospital,to_service
  from public.profiles
  where id=r.to_id and account_status='active';

  if from_hospital is null
     or to_hospital is null
     or from_hospital is distinct from to_hospital
  then
    raise exception 'Les échanges sont autorisés uniquement entre médecins du même hôpital';
  end if;

  if r.type='exchange' then
    select * into target
    from public.planning_entries
    where id=r.target_planning_entry_id and deleted_at is null
    for update;

    if not found
       or target.owner_id<>r.to_id
       or target.shift_id='conge'
       or target.date_str<>r.target_date_str
       or target.shift_id<>r.target_shift_id
       or public.guard_has_started(target.date_str,target.shift_id)
    then
      raise exception 'La garde cible a été modifiée, supprimée ou a déjà commencé';
    end if;

    involves_service :=
      source.shift_id like 'service-%'
      or target.shift_id like 'service-%';

    if involves_service then
      if nullif(trim(from_service),'') is null
         or nullif(trim(to_service),'') is null
         or trim(from_service) is distinct from trim(to_service)
      then
        raise exception 'Toute garde de Service ne peut être échangée qu’entre médecins du même service';
      end if;
    end if;

    auto_service_exchange :=
      source.shift_id like 'service-%'
      and target.shift_id like 'service-%';
  end if;

  -- SERVICE <-> SERVICE, même hôpital + même service : le consentement
  -- des deux médecins suffit. Aucun ADMIN n'intervient.
  if auto_service_exchange then
    if not public.planning_month_is_approved(r.from_id,target.date_str)
       or not public.planning_month_is_approved(r.to_id,source.date_str)
    then
      raise exception 'Les mois de destination ne sont pas tous validés';
    end if;

    perform set_config('huim6.review_request','1',true);

    if source.date_str=target.date_str then
      update public.planning_entries
      set shift_id=target.shift_id
      where id=source.id;

      update public.planning_entries
      set shift_id=source.shift_id
      where id=target.id;
    else
      if exists(
        select 1 from public.planning_entries
        where owner_id=r.to_id
          and date_str=source.date_str
          and deleted_at is null
          and id<>target.id
      ) then
        raise exception 'Conflit de planning du destinataire';
      end if;

      if exists(
        select 1 from public.planning_entries
        where owner_id=r.from_id
          and date_str=target.date_str
          and deleted_at is null
          and id<>source.id
      ) then
        raise exception 'Conflit de planning du demandeur';
      end if;

      update public.planning_entries
      set date_str=target.date_str,
          shift_id=target.shift_id
      where id=source.id;

      update public.planning_entries
      set date_str=source.date_str,
          shift_id=source.shift_id
      where id=target.id;
    end if;

    update public.exchange_requests
    set status='approved'
    where id=p_request_id;

    perform public.write_audit(
      'exchange.accepted',
      'exchange_request',
      p_request_id,
      r.to_id,
      r.to_name,
      null,
      jsonb_build_object(
        'auto_service_exchange',true,
        'same_service',true,
        'admin_required',false
      )
    );

    perform public.write_audit(
      'exchange.approved',
      'exchange_request',
      p_request_id,
      null,
      null,
      null,
      jsonb_build_object(
        'auto_service_exchange',true,
        'same_service',true,
        'admin_required',false
      )
    );

    return;
  end if;

  -- Transferts et tout échange impliquant URGENCES : validation ADMIN.
  update public.exchange_requests
  set status='pendingAdmin'
  where id=p_request_id;

  perform public.write_audit(
    'exchange.accepted',
    'exchange_request',
    p_request_id,
    r.to_id,
    r.to_name,
    null,
    jsonb_build_object(
      'admin_required',true,
      'involves_service',involves_service
    )
  );
end;
$$;

grant execute on function public.respond_shift_request(text,text) to authenticated;


-- ================================================================
-- V11.3.0 - médias d'astreinte partagés et plannings officiels PDF
-- Pour une installation existante, exécuter plutôt :
-- patch_v11_3_0_shared_astreinte_official_pdfs.sql
-- ================================================================
create table if not exists public.shared_resources (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('astreinte_photo','official_pdf')),
  slot text,
  storage_path text not null unique,
  display_name text not null,
  mime_type text not null,
  uploaded_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((kind='astreinte_photo' and slot is null) or (kind='official_pdf' and slot in ('hm6_bouskoura','hm6_rabat','hck_casa'))),
  unique(kind, slot)
);
alter table public.shared_resources enable row level security;
drop policy if exists shared_resources_read on public.shared_resources;
create policy shared_resources_read on public.shared_resources for select to authenticated using (true);
drop policy if exists shared_resources_admin_insert on public.shared_resources;
create policy shared_resources_admin_insert on public.shared_resources for insert to authenticated with check (public.is_admin() and uploaded_by=auth.uid());
drop policy if exists shared_resources_admin_update on public.shared_resources;
create policy shared_resources_admin_update on public.shared_resources for update to authenticated using (public.is_admin()) with check (public.is_admin() and uploaded_by=auth.uid());
drop policy if exists shared_resources_admin_delete on public.shared_resources;
create policy shared_resources_admin_delete on public.shared_resources for delete to authenticated using (public.is_admin());
grant select, insert, update, delete on public.shared_resources to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('gardeflow-shared','gardeflow-shared',false,26214400,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do update set public=excluded.public,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists gardeflow_shared_read on storage.objects;
create policy gardeflow_shared_read on storage.objects for select to authenticated using (bucket_id='gardeflow-shared');
drop policy if exists gardeflow_shared_admin_insert on storage.objects;
create policy gardeflow_shared_admin_insert on storage.objects for insert to authenticated with check (bucket_id='gardeflow-shared' and public.is_admin());
drop policy if exists gardeflow_shared_admin_update on storage.objects;
create policy gardeflow_shared_admin_update on storage.objects for update to authenticated using (bucket_id='gardeflow-shared' and public.is_admin()) with check (bucket_id='gardeflow-shared' and public.is_admin());
drop policy if exists gardeflow_shared_admin_delete on storage.objects;
create policy gardeflow_shared_admin_delete on storage.objects for delete to authenticated using (bucket_id='gardeflow-shared' and public.is_admin());
