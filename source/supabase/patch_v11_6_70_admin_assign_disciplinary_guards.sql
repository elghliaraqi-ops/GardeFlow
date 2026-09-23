-- GardeFlow 11.6.70
-- Attribution manuelle d'une ou plusieurs gardes disciplinaires par un administrateur.

create or replace function public.admin_assign_disciplinary_guards(
  p_owner_id uuid,
  p_assignments jsonb,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_profile public.profiles%rowtype;
  v_item jsonb;
  v_date date;
  v_shift text;
  v_existing public.planning_entries%rowtype;
  v_entry_id text;
  v_ids text[] := array[]::text[];
  v_seen_dates date[] := array[]::date[];
  v_applied int := 0;
  v_reason text := nullif(trim(coalesce(p_reason,'')),'');
begin
  if not public.is_admin() then
    raise exception 'Action réservée à l’administrateur';
  end if;

  select * into v_profile
  from public.profiles
  where id=p_owner_id
    and account_status='active';
  if not found then
    raise exception 'Médecin actif introuvable';
  end if;

  if jsonb_typeof(coalesce(p_assignments,'null'::jsonb)) <> 'array'
     or jsonb_array_length(p_assignments) < 1 then
    raise exception 'Ajoutez au moins une garde disciplinaire';
  end if;
  if jsonb_array_length(p_assignments) > 31 then
    raise exception 'Maximum 31 gardes par attribution';
  end if;

  -- Autorise la fonction administrateur à ajuster une garde déjà disciplinaire
  -- tout en conservant le verrou pour toutes les autres opérations.
  perform set_config('gardeflow.official_import','1',true);

  for v_item in select value from jsonb_array_elements(p_assignments)
  loop
    begin
      v_date := nullif(v_item->>'date','')::date;
      v_shift := nullif(v_item->>'shift_id','');
    exception when others then
      raise exception 'Date ou type de garde invalide';
    end;

    if v_date is null then
      raise exception 'Date de garde manquante';
    end if;
    if v_shift not in (
      'service-jour','service-24h','service-nuit',
      'urg-jour','urg-24h','urg-nuit'
    ) then
      raise exception 'Type de garde invalide pour le %', v_date;
    end if;
    if v_date = any(v_seen_dates) then
      raise exception 'La date % est présente plusieurs fois dans la même attribution', v_date;
    end if;
    v_seen_dates := array_append(v_seen_dates,v_date);

    if public.guard_has_started(v_date,v_shift) then
      raise exception 'La garde du % est déjà commencée ou passée', v_date;
    end if;

    select * into v_existing
    from public.planning_entries
    where owner_id=p_owner_id
      and date_str=v_date
      and deleted_at is null
    for update;

    if found then
      if not coalesce(v_existing.is_disciplinary,false) then
        raise exception '% a déjà une affectation le %. Supprimez ou déplacez d’abord cette affectation.',
          trim(v_profile.prenom || ' ' || v_profile.nom), v_date;
      end if;

      update public.exchange_requests
      set status='cancelled'
      where status in ('pendingB','pendingAdmin')
        and (planning_entry_id=v_existing.id or target_planning_entry_id=v_existing.id);

      update public.planning_entries
      set shift_id=v_shift,
          owner_phone=v_profile.phone,
          owner_name=trim(v_profile.prenom || ' ' || v_profile.nom),
          leave_request_id=null,
          is_disciplinary=true
      where id=v_existing.id;
      v_entry_id := v_existing.id;
    else
      v_entry_id := 'disc-' || replace(gen_random_uuid()::text,'-','');
      insert into public.planning_entries(
        id,date_str,shift_id,owner_id,owner_phone,owner_name,
        leave_request_id,is_disciplinary,created_at
      ) values (
        v_entry_id,v_date,v_shift,v_profile.id,v_profile.phone,
        trim(v_profile.prenom || ' ' || v_profile.nom),
        null,true,now()
      );
    end if;

    perform public.write_audit(
      'planning.disciplinary_assigned',
      'planning_entry',
      v_entry_id,
      v_profile.id,
      trim(v_profile.prenom || ' ' || v_profile.nom),
      v_reason,
      jsonb_build_object(
        'date',v_date,
        'shift_id',v_shift,
        'manual_admin_assignment',true
      )
    );

    v_ids := array_append(v_ids,v_entry_id);
    v_applied := v_applied + 1;
  end loop;

  return jsonb_build_object(
    'applied',v_applied,
    'entry_ids',to_jsonb(v_ids),
    'owner_id',p_owner_id
  );
end;
$$;

revoke all on function public.admin_assign_disciplinary_guards(uuid,jsonb,text) from public,anon;
grant execute on function public.admin_assign_disciplinary_guards(uuid,jsonb,text) to authenticated;
