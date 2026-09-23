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
