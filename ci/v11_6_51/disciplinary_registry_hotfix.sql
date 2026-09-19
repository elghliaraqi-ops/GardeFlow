-- GardeFlow V11.6.51 — hotfix gardes disciplinaires
-- Objectif : le verrou ne dépend plus uniquement du booléen de la ligne active.
-- Une garde détectée rouge est enregistrée dans un registre lié à la version
-- courante du PDF officiel. Toute modification/suppression manuelle de cette
-- date est ensuite bloquée, même si la ligne a été recréée.

create table if not exists public.official_disciplinary_guards (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  date_str date not null,
  shift_id text not null,
  resource_id uuid not null references public.shared_resources(id) on delete cascade,
  resource_updated_at timestamptz not null,
  detected_at timestamptz not null default now(),
  primary key(owner_id, date_str, resource_id, resource_updated_at)
);

create index if not exists official_disciplinary_guards_owner_date_idx
  on public.official_disciplinary_guards(owner_id, date_str);

alter table public.official_disciplinary_guards enable row level security;
revoke all on table public.official_disciplinary_guards from public, anon, authenticated;

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
  select exists(
    select 1
    from public.official_disciplinary_guards d
    join public.shared_resources r
      on r.id = d.resource_id
     and r.kind = 'official_pdf'
     and r.updated_at = d.resource_updated_at
    where d.owner_id = p_owner_id
      and d.date_str = p_date
  );
$$;

revoke all on function public.is_current_disciplinary_guard(uuid,date)
  from public, anon, authenticated;

create or replace function public.sync_disciplinary_registry_from_entry()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_disciplinary
     and new.source_resource_id is not null
     and new.source_resource_updated_at is not null then
    insert into public.official_disciplinary_guards(
      owner_id,
      date_str,
      shift_id,
      resource_id,
      resource_updated_at,
      detected_at
    )
    values(
      new.owner_id,
      new.date_str,
      new.shift_id,
      new.source_resource_id,
      new.source_resource_updated_at,
      now()
    )
    on conflict(owner_id,date_str,resource_id,resource_updated_at)
    do update
      set shift_id = excluded.shift_id,
          detected_at = now();
  end if;

  if tg_op = 'UPDATE'
     and old.is_disciplinary
     and not new.is_disciplinary
     and coalesce(current_setting('gardeflow.official_import', true), '0') = '1'
     and old.source_resource_id is not null
     and old.source_resource_updated_at is not null then
    delete from public.official_disciplinary_guards d
    where d.owner_id = old.owner_id
      and d.date_str = old.date_str
      and d.resource_id = old.source_resource_id
      and d.resource_updated_at = old.source_resource_updated_at;
  end if;

  return new;
end;
$$;

drop trigger if exists sync_disciplinary_registry_from_entry_trigger
  on public.planning_entries;
create trigger sync_disciplinary_registry_from_entry_trigger
after insert or update of is_disciplinary, source_resource_id,
  source_resource_updated_at, shift_id
on public.planning_entries
for each row execute function public.sync_disciplinary_registry_from_entry();

create or replace function public.protect_disciplinary_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_disc boolean := false;
  v_new_disc boolean := false;
begin
  if tg_op = 'INSERT' then
    v_new_disc := public.is_current_disciplinary_guard(new.owner_id, new.date_str);

    if v_new_disc then
      if coalesce(current_setting('gardeflow.official_import', true), '0') = '1' then
        new.is_disciplinary := true;
        return new;
      end if;

      raise exception 'Garde disciplinaire : cette date est verrouillée. Seul un administrateur peut la supprimer.';
    end if;

    return new;
  end if;

  v_old_disc := old.is_disciplinary
    or public.is_current_disciplinary_guard(old.owner_id, old.date_str);

  if tg_op = 'DELETE' then
    if not v_old_disc then
      return old;
    end if;

    if coalesce(current_setting('gardeflow.official_import', true), '0') = '1' then
      return old;
    end if;

    if coalesce(current_setting('gardeflow.disciplinary_admin_delete', true), '0') = '1'
       and public.is_admin() then
      return old;
    end if;

    raise exception 'Garde disciplinaire : suppression réservée à l’administrateur.';
  end if;

  v_new_disc := public.is_current_disciplinary_guard(new.owner_id, new.date_str);

  if v_old_disc and (
       new.date_str is distinct from old.date_str
       or new.shift_id is distinct from old.shift_id
       or new.owner_id is distinct from old.owner_id
       or new.deleted_at is distinct from old.deleted_at
       or new.is_disciplinary is distinct from old.is_disciplinary
     ) then

    if coalesce(current_setting('gardeflow.official_import', true), '0') = '1' then
      return new;
    end if;

    if coalesce(current_setting('gardeflow.disciplinary_admin_delete', true), '0') = '1'
       and public.is_admin()
       and old.deleted_at is null
       and new.deleted_at is not null
       and new.date_str is not distinct from old.date_str
       and new.shift_id is not distinct from old.shift_id
       and new.owner_id is not distinct from old.owner_id
       and new.is_disciplinary is not distinct from old.is_disciplinary then
      return new;
    end if;

    raise exception 'Garde disciplinaire : annulation, modification et échange interdits. Seul un administrateur peut la supprimer.';
  end if;

  if v_new_disc then
    new.is_disciplinary := true;
  end if;

  return new;
end;
$$;

drop trigger if exists protect_disciplinary_guard_trigger
  on public.planning_entries;
create trigger protect_disciplinary_guard_trigger
before insert or update or delete on public.planning_entries
for each row execute function public.protect_disciplinary_guard();

-- Les demandes d'échange/transfert restent interdites si la garde est
-- disciplinaire dans la ligne OU dans le registre officiel.
create or replace function public.reject_disciplinary_exchange_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status in ('declinedB', 'rejectedAdmin', 'cancelled') then
    return new;
  end if;

  if exists (
    select 1
    from public.planning_entries e
    where e.id = new.planning_entry_id
      and e.deleted_at is null
      and (
        e.is_disciplinary
        or public.is_current_disciplinary_guard(e.owner_id, e.date_str)
      )
  ) then
    raise exception 'Une garde disciplinaire ne peut être ni transférée ni échangée.';
  end if;

  if new.target_planning_entry_id is not null and exists (
    select 1
    from public.planning_entries e
    where e.id = new.target_planning_entry_id
      and e.deleted_at is null
      and (
        e.is_disciplinary
        or public.is_current_disciplinary_guard(e.owner_id, e.date_str)
      )
  ) then
    raise exception 'Une garde disciplinaire ne peut être ni transférée ni échangée.';
  end if;

  return new;
end;
$$;

drop trigger if exists reject_disciplinary_exchange_request_trigger
  on public.exchange_requests;
create trigger reject_disciplinary_exchange_request_trigger
before insert or update on public.exchange_requests
for each row execute function public.reject_disciplinary_exchange_request();


-- ---------------------------------------------------------------------------
-- Forcer une nouvelle lecture des PDF avec le détecteur rouge corrigé.
-- Les wrappers V11.6.47 écrivent encore leur ancienne révision ; ce trigger
-- la convertit en V11.6.51 après la nouvelle analyse, afin d'éviter de
-- retraiter le PDF à chaque ouverture.
-- ---------------------------------------------------------------------------
create or replace function public.normalize_v11_6_51_roster_revision()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.sync_revision = 'v11.6.47-r1' then
    new.sync_revision := 'v11.6.51-r1';
  end if;
  return new;
end;
$$;

drop trigger if exists normalize_v11_6_51_profile_sync_revision
  on public.official_roster_profile_sync;
create trigger normalize_v11_6_51_profile_sync_revision
before insert or update of sync_revision
on public.official_roster_profile_sync
for each row execute function public.normalize_v11_6_51_roster_revision();

drop trigger if exists normalize_v11_6_51_import_run_revision
  on public.official_roster_import_runs;
create trigger normalize_v11_6_51_import_run_revision
before insert or update of sync_revision
on public.official_roster_import_runs
for each row execute function public.normalize_v11_6_51_roster_revision();

create or replace function public.official_roster_profile_sync_is_current(
  p_resource_id uuid,
  p_resource_updated_at timestamptz,
  p_profile_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_signature text;
  v_revision constant text := 'v11.6.51-r1';
begin
  if auth.uid() is null then raise exception 'Session requise'; end if;
  if p_profile_id <> auth.uid() and not public.is_admin() then
    raise exception 'Accès refusé';
  end if;

  select * into v_profile
  from public.profiles p
  where p.id = p_profile_id and p.account_status = 'active';
  if not found then return false; end if;

  v_signature := md5(
    lower(trim(coalesce(v_profile.prenom,''))) || '|' ||
    lower(trim(coalesce(v_profile.nom,''))) || '|' ||
    coalesce(v_profile.phone,'') || '|' ||
    coalesce(v_profile.hospital,'') || '|' ||
    coalesce(v_profile.account_status,'')
  );

  return exists(
    select 1 from public.official_roster_profile_sync ps
    where ps.resource_id = p_resource_id
      and ps.resource_updated_at = p_resource_updated_at
      and ps.profile_id = p_profile_id
      and ps.profile_signature = v_signature
      and ps.sync_revision = v_revision
  );
end;
$$;

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
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;

  return exists(
    select 1 from public.official_roster_import_runs r
    where r.resource_id = p_resource_id
      and r.resource_updated_at = p_resource_updated_at
      and r.sync_revision = 'v11.6.51-r1'
  );
end;
$$;
