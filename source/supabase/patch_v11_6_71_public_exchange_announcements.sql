-- GardeFlow 11.6.70
-- Fil public d'annonces de gardes à échanger.

create table if not exists public.public_exchange_announcements (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  author_name text not null default '',
  author_phone text not null default '',
  hospital text not null default '',
  service text not null default '',
  planning_entry_id text not null references public.planning_entries(id),
  date_str date not null,
  shift_id text not null,
  message text not null default '',
  status text not null default 'active' check (status in ('active','closed')),
  created_at timestamptz not null default now(),
  closed_at timestamptz
);

create index if not exists public_exchange_announcements_created_idx
  on public.public_exchange_announcements(created_at desc);

create index if not exists public_exchange_announcements_hospital_idx
  on public.public_exchange_announcements(hospital, created_at desc);

create unique index if not exists public_exchange_announcements_one_active_per_guard_idx
  on public.public_exchange_announcements(planning_entry_id)
  where status='active';

alter table public.public_exchange_announcements enable row level security;
alter table public.public_exchange_announcements replica identity full;

create or replace function public.prepare_public_exchange_announcement()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  uid uuid := auth.uid();
  p public.profiles%rowtype;
  e public.planning_entries%rowtype;
begin
  if uid is null then
    raise exception 'Authentification requise';
  end if;

  if tg_op='UPDATE' then
    if old.author_id<>uid then
      raise exception 'Action non autorisée';
    end if;

    -- Une annonce publiée est immuable : son auteur peut uniquement la fermer.
    new.author_id := old.author_id;
    new.author_name := old.author_name;
    new.author_phone := old.author_phone;
    new.hospital := old.hospital;
    new.service := old.service;
    new.planning_entry_id := old.planning_entry_id;
    new.date_str := old.date_str;
    new.shift_id := old.shift_id;
    new.message := old.message;
    new.created_at := old.created_at;

    if new.status not in ('active','closed') then
      raise exception 'Statut invalide';
    end if;
    if old.status='closed' and new.status<>'closed' then
      raise exception 'Une annonce fermée ne peut pas être rouverte';
    end if;
    if new.status='closed' and old.status<>'closed' then
      new.closed_at := now();
    else
      new.closed_at := old.closed_at;
    end if;
    return new;
  end if;

  select * into p
  from public.profiles
  where id=uid and account_status='active';
  if not found then
    raise exception 'Compte actif requis';
  end if;

  if new.author_id is distinct from uid then
    raise exception 'Auteur invalide';
  end if;

  select * into e
  from public.planning_entries
  where id=new.planning_entry_id
    and owner_id=uid
    and deleted_at is null
  for share;

  if not found then
    raise exception 'Garde introuvable';
  end if;
  if e.shift_id='conge' then
    raise exception 'Un congé ne peut pas être publié';
  end if;
  if coalesce(e.is_disciplinary,false) then
    raise exception 'Une garde disciplinaire ne peut pas être publiée';
  end if;
  if public.guard_has_started(e.date_str,e.shift_id) then
    raise exception 'Une garde commencée ou passée ne peut pas être publiée';
  end if;
  if not public.planning_month_is_approved(uid,e.date_str) then
    raise exception 'Le calendrier doit être validé avant publication';
  end if;

  new.author_name := trim(concat_ws(' ',p.prenom,p.nom));
  new.author_phone := p.phone;
  new.hospital := p.hospital;
  new.service := p.service;
  new.date_str := e.date_str;
  new.shift_id := e.shift_id;
  new.status := 'active';
  new.closed_at := null;
  new.message := left(nullif(trim(coalesce(new.message,'')),''),500);
  if new.message is null then
    new.message := 'Je souhaite échanger cette garde.';
  end if;
  return new;
end;
$$;

revoke all on function public.prepare_public_exchange_announcement() from public;

DROP TRIGGER IF EXISTS public_exchange_announcement_prepare ON public.public_exchange_announcements;
create trigger public_exchange_announcement_prepare
before insert or update on public.public_exchange_announcements
for each row execute function public.prepare_public_exchange_announcement();

drop policy if exists public_exchange_announcements_select on public.public_exchange_announcements;
create policy public_exchange_announcements_select
on public.public_exchange_announcements
for select to authenticated
using (public.current_account_active());

drop policy if exists public_exchange_announcements_insert on public.public_exchange_announcements;
create policy public_exchange_announcements_insert
on public.public_exchange_announcements
for insert to authenticated
with check (
  public.current_account_active()
  and author_id=auth.uid()
  and status='active'
);

drop policy if exists public_exchange_announcements_update on public.public_exchange_announcements;
create policy public_exchange_announcements_update
on public.public_exchange_announcements
for update to authenticated
using (
  public.current_account_active()
  and author_id=auth.uid()
)
with check (
  public.current_account_active()
  and author_id=auth.uid()
);

grant select,insert,update on public.public_exchange_announcements to authenticated;

-- Active le flux temps réel sans échouer si la table a déjà été ajoutée.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname='supabase_realtime'
      and schemaname='public'
      and tablename='public_exchange_announcements'
  ) then
    alter publication supabase_realtime add table public.public_exchange_announcements;
  end if;
end;
$$;
