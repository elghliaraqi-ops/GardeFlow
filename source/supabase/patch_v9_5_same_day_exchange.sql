-- HUIM6 Planning V9.5
-- À exécuter UNE FOIS dans Supabase > SQL Editor pour autoriser les échanges
-- de gardes le même jour (ex. Jour ↔ Nuit le 26/09).

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
      -- Même date : on permute seulement le type de garde pour éviter la
      -- contrainte unique(owner_phone,date_str) tout en réalisant l'échange.
      update public.planning_entries set shift_id=target.shift_id where id=source.id;
      update public.planning_entries set shift_id=source.shift_id where id=target.id;
    else
      if exists(select 1 from public.planning_entries where owner_phone=r.to_phone and date_str=source.date_str and id<>target.id) then
        raise exception 'Conflit de planning du destinataire';
      end if;
      if exists(select 1 from public.planning_entries where owner_phone=r.from_phone and date_str=target.date_str and id<>source.id) then
        raise exception 'Conflit de planning du demandeur';
      end if;
      update public.planning_entries set owner_phone=r.to_phone, owner_name=r.to_name where id=source.id;
      update public.planning_entries set owner_phone=r.from_phone, owner_name=r.from_name where id=target.id;
    end if;
  end if;
  update public.exchange_requests set status='approved' where id=p_request_id;
end;
$$;

grant execute on function public.review_shift_request(text,text) to authenticated;
