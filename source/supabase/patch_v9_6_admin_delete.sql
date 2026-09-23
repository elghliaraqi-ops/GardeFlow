-- HUIM6 Planning V9.6
-- À exécuter UNE FOIS dans Supabase > SQL Editor pour un projet déjà installé.

-- 1) Archivage logique des gardes supprimées afin de préserver l'historique
-- des transferts et échanges.
alter table public.planning_entries
  add column if not exists deleted_at timestamptz;

-- L'ancienne contrainte UNIQUE empêcherait la recréation d'une garde sur une
-- date dont l'ancienne affectation a été archivée. On la remplace par un
-- index unique portant uniquement sur les gardes actives.
alter table public.planning_entries
  drop constraint if exists planning_entries_owner_phone_date_str_key;

drop index if exists public.planning_owner_date_active_uidx;
create unique index planning_owner_date_active_uidx
  on public.planning_entries(owner_phone,date_str)
  where deleted_at is null;

-- 2) Suppression prioritaire admin.
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

  -- Si la garde participe encore à une demande, l'admin l'annule d'abord.
  update public.exchange_requests
  set status='cancelled'
  where status in ('pendingB','pendingAdmin')
    and (planning_entry_id=p_entry_id or target_planning_entry_id=p_entry_id);

  -- Soft-delete : la garde disparaît du planning, mais les demandes terminées
  -- gardent leurs références et restent consultables dans l'historique.
  update public.planning_entries
  set deleted_at=now()
  where id=p_entry_id;
end;
$$;

grant execute on function public.admin_delete_planning(text) to authenticated;
