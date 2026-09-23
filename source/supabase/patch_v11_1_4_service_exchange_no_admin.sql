-- GardeFlow 11.1.4
-- Les échanges 100 % SERVICE (source et cible service-*) sont appliqués
-- immédiatement après acceptation du destinataire, sans validation ADMIN.
-- Les transferts et tout échange impliquant les Urgences restent inchangés.

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
  auto_service_exchange boolean := false;
begin
  select * into r
  from public.exchange_requests
  where id=p_request_id
  for update;

  if not found then raise exception 'Demande introuvable'; end if;
  if r.to_id<>auth.uid() then raise exception 'Non autorisé'; end if;
  if r.status<>'pendingB' then raise exception 'Demande déjà traitée'; end if;
  if not public.current_account_active() then raise exception 'Compte actif requis'; end if;

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

    auto_service_exchange :=
      source.shift_id like 'service-%'
      and target.shift_id like 'service-%';
  end if;

  if p_action='decline' then
    update public.exchange_requests set status='declinedB' where id=p_request_id;
    perform public.write_audit('exchange.declined','exchange_request',p_request_id,r.to_id,r.to_name);
    return;
  elsif p_action<>'accept' then
    raise exception 'Action invalide';
  end if;

  -- Cas spécial demandé : échange SERVICE ↔ SERVICE.
  -- Le consentement des deux médecins suffit ; aucun ADMIN n'intervient.
  if auto_service_exchange then
    select hospital into from_hospital
    from public.profiles
    where id=r.from_id and account_status='active';

    select hospital into to_hospital
    from public.profiles
    where id=r.to_id and account_status='active';

    if from_hospital is null
       or to_hospital is null
       or from_hospital is distinct from to_hospital
    then
      raise exception 'Participants invalides ou inter-établissements';
    end if;

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
      jsonb_build_object('auto_service_exchange',true)
    );

    perform public.write_audit(
      'exchange.approved',
      'exchange_request',
      p_request_id,
      null,
      null,
      null,
      jsonb_build_object('auto_service_exchange',true,'admin_required',false)
    );

    return;
  end if;

  -- Comportement historique inchangé : transfert et échanges impliquant
  -- les Urgences attendent toujours une validation administrateur.
  update public.exchange_requests
  set status='pendingAdmin'
  where id=p_request_id;

  perform public.write_audit('exchange.accepted','exchange_request',p_request_id,r.to_id,r.to_name);
end;
$$;

grant execute on function public.respond_shift_request(text,text) to authenticated;
