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
