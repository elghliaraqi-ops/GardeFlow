-- HUIM6 Planning V9.8.2
-- Correctif des échanges sur deux dates différentes.
-- Exemple attendu : Dr A Jour le 16 <-> Dr B Nuit le 27.
-- À exécuter UNE FOIS dans Supabase > SQL Editor après la V9.7/V9.8.

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

  select * into r
  from public.exchange_requests
  where id=p_request_id
  for update;

  if not found then raise exception 'Demande introuvable'; end if;
  if r.status<>'pendingAdmin' then raise exception 'Demande non prête pour validation'; end if;

  if p_action='reject' then
    update public.exchange_requests set status='rejectedAdmin' where id=p_request_id;
    return;
  elsif p_action<>'approve' then
    raise exception 'Action invalide';
  end if;

  perform set_config('huim6.review_request','1',true);

  select hospital into from_hospital from public.profiles where phone=r.from_phone;
  select hospital into to_hospital from public.profiles where phone=r.to_phone;
  if from_hospital is distinct from to_hospital then
    raise exception 'Transfert/échange inter-établissements interdit';
  end if;

  select * into source
  from public.planning_entries
  where id=r.planning_entry_id and deleted_at is null
  for update;

  if not found or source.owner_phone<>r.from_phone then
    raise exception 'Garde source modifiée ou supprimée';
  end if;

  if r.type='transfer' then
    if exists(
      select 1 from public.planning_entries
      where owner_phone=r.to_phone
        and date_str=source.date_str
        and deleted_at is null
    ) then
      raise exception 'Le destinataire a déjà une affectation ce jour-là';
    end if;

    update public.planning_entries
    set owner_phone=r.to_phone, owner_name=r.to_name
    where id=source.id;
  else
    select * into target
    from public.planning_entries
    where id=r.target_planning_entry_id and deleted_at is null
    for update;

    if not found or target.owner_phone<>r.to_phone then
      raise exception 'Garde cible modifiée ou supprimée';
    end if;

    if exists(
      select 1 from public.planning_entries
      where owner_phone=r.to_phone
        and date_str=source.date_str
        and deleted_at is null
        and id<>target.id
    ) then
      raise exception 'Conflit de planning du destinataire';
    end if;

    if exists(
      select 1 from public.planning_entries
      where owner_phone=r.from_phone
        and date_str=target.date_str
        and deleted_at is null
        and id<>source.id
    ) then
      raise exception 'Conflit de planning du demandeur';
    end if;

    if source.date_str=target.date_str then
      -- Même date : A garde sa date mais reçoit le type de garde de B et inversement.
      update public.planning_entries set shift_id=target.shift_id where id=source.id;
      update public.planning_entries set shift_id=source.shift_id where id=target.id;
    else
      -- Dates différentes : chaque médecin conserve sa ligne/propriétaire.
      -- On échange la garde elle-même : date + type de garde.
      -- Exemple : A Jour 16 devient Nuit 27 ; B Nuit 27 devient Jour 16.
      update public.planning_entries
      set date_str=target.date_str,
          shift_id=target.shift_id
      where id=source.id;

      update public.planning_entries
      set date_str=source.date_str,
          shift_id=source.shift_id
      where id=target.id;
    end if;
  end if;

  update public.exchange_requests set status='approved' where id=p_request_id;
end;
$$;

grant execute on function public.review_shift_request(text,text) to authenticated;
