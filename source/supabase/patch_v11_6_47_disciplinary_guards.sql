-- GardeFlow V11.6.47 — gardes disciplinaires détectées par les noms rouges des PDF

alter table public.planning_entries
  add column if not exists is_disciplinary boolean not null default false;

alter table public.official_roster_import_runs
  add column if not exists sync_revision text not null default 'legacy';

-- ---------------------------------------------------------------------------
-- Protection serveur : une garde disciplinaire ne peut être ni modifiée,
-- ni annulée, ni transférée/échangée. Seuls l'import PDF officiel et la
-- suppression explicite par un administrateur peuvent la modifier.
-- ---------------------------------------------------------------------------
create or replace function public.protect_disciplinary_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    if not old.is_disciplinary then
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

  if old.is_disciplinary and (
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

  return new;
end;
$$;

drop trigger if exists protect_disciplinary_guard_trigger on public.planning_entries;
create trigger protect_disciplinary_guard_trigger
before update or delete on public.planning_entries
for each row execute function public.protect_disciplinary_guard();

create or replace function public.reject_disciplinary_exchange_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Refuser/annuler une ancienne demande reste toujours possible.
  if new.status in ('declinedB', 'rejectedAdmin', 'cancelled') then
    return new;
  end if;

  if exists (
    select 1
    from public.planning_entries e
    where e.id = new.planning_entry_id
      and e.deleted_at is null
      and e.is_disciplinary
  ) then
    raise exception 'Une garde disciplinaire ne peut être ni transférée ni échangée.';
  end if;

  if new.target_planning_entry_id is not null and exists (
    select 1
    from public.planning_entries e
    where e.id = new.target_planning_entry_id
      and e.deleted_at is null
      and e.is_disciplinary
  ) then
    raise exception 'Une garde disciplinaire ne peut être ni transférée ni échangée.';
  end if;

  return new;
end;
$$;

drop trigger if exists reject_disciplinary_exchange_request_trigger on public.exchange_requests;
create trigger reject_disciplinary_exchange_request_trigger
before insert or update on public.exchange_requests
for each row execute function public.reject_disciplinary_exchange_request();

-- ---------------------------------------------------------------------------
-- Conserver les importeurs V11.6.46 sous un nom interne et envelopper leur
-- fonctionnement : la logique d'import existante reste intacte, puis la couche
-- V11.6.47 applique le statut disciplinaire issu de la couleur rouge du PDF.
-- ---------------------------------------------------------------------------
do $do$
begin
  if to_regprocedure('public.import_official_emergency_roster(uuid,timestamp with time zone,jsonb,jsonb)') is not null
     and to_regprocedure('public.import_official_emergency_roster_legacy_v46(uuid,timestamp with time zone,jsonb,jsonb)') is null then
    execute 'alter function public.import_official_emergency_roster(uuid,timestamp with time zone,jsonb,jsonb) rename to import_official_emergency_roster_legacy_v46';
  end if;

  if to_regprocedure('public.import_official_emergency_roster_for_profile(uuid,timestamp with time zone,uuid,jsonb,jsonb)') is not null
     and to_regprocedure('public.import_official_emergency_roster_for_profile_legacy_v46(uuid,timestamp with time zone,uuid,jsonb,jsonb)') is null then
    execute 'alter function public.import_official_emergency_roster_for_profile(uuid,timestamp with time zone,uuid,jsonb,jsonb) rename to import_official_emergency_roster_for_profile_legacy_v46';
  end if;
end
$do$;

revoke execute on function public.import_official_emergency_roster_legacy_v46(uuid,timestamptz,jsonb,jsonb) from public;
revoke execute on function public.import_official_emergency_roster_legacy_v46(uuid,timestamptz,jsonb,jsonb) from anon, authenticated;
revoke execute on function public.import_official_emergency_roster_for_profile_legacy_v46(uuid,timestamptz,uuid,jsonb,jsonb) from public;
revoke execute on function public.import_official_emergency_roster_for_profile_legacy_v46(uuid,timestamptz,uuid,jsonb,jsonb) from anon, authenticated;

create or replace function public.import_official_emergency_roster(
  p_resource_id uuid,
  p_resource_updated_at timestamptz,
  p_assignments jsonb,
  p_unmatched_cells jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_resource public.shared_resources%rowtype;
  v_profile public.profiles%rowtype;
  v_entry public.planning_entries%rowtype;
  v_item jsonb;
  v_profile_id uuid;
  v_date date;
  v_shift text;
  v_disciplinary boolean;
  v_hospital text;
  v_revision constant text := 'v11.6.47-r1';
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;

  select * into v_resource
  from public.shared_resources
  where id = p_resource_id and kind = 'official_pdf'
  for update;
  if not found then raise exception 'Planning officiel introuvable'; end if;
  if v_resource.updated_at is distinct from p_resource_updated_at then
    raise exception 'Le PDF a été remplacé pendant son analyse. Relancer la synchronisation.';
  end if;

  v_hospital := case v_resource.slot
    when 'hm6_bouskoura' then 'Hôpital Universitaire International Mohammed VI de Bouskoura'
    when 'hm6_rabat' then 'Hôpital Universitaire International Mohammed VI de Rabat'
    when 'hck_casa' then 'Hôpital Universitaire International Cheikh Khalifa de Casablanca'
    else null
  end;
  if v_hospital is null then raise exception 'Établissement du PDF invalide'; end if;

  v_result := public.import_official_emergency_roster_legacy_v46(
    p_resource_id,
    p_resource_updated_at,
    p_assignments,
    p_unmatched_cells
  );

  perform set_config('gardeflow.official_import', '1', true);

  for v_item in select value from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb))
  loop
    begin
      v_profile_id := nullif(v_item->>'profile_id','')::uuid;
      v_date := nullif(v_item->>'date','')::date;
      v_shift := v_item->>'shift_id';
      v_disciplinary := coalesce(nullif(v_item->>'is_disciplinary','')::boolean, false);
    exception when others then
      continue;
    end;

    if v_shift not in ('urg-jour','urg-nuit','urg-24h') then continue; end if;

    select * into v_profile
    from public.profiles
    where id = v_profile_id
      and account_status = 'active'
      and hospital = v_hospital;
    if not found then continue; end if;

    select * into v_entry
    from public.planning_entries
    where owner_id = v_profile_id
      and date_str = v_date
      and deleted_at is null
    for update;

    if v_disciplinary then
      if found then
        update public.exchange_requests
        set status = 'cancelled'
        where status in ('pendingB','pendingAdmin')
          and (planning_entry_id = v_entry.id or target_planning_entry_id = v_entry.id);

        update public.planning_entries
        set shift_id = v_shift,
            owner_phone = v_profile.phone,
            owner_name = trim(v_profile.prenom || ' ' || v_profile.nom),
            leave_request_id = null,
            source_type = 'official_emergency',
            source_resource_id = p_resource_id,
            source_resource_updated_at = p_resource_updated_at,
            is_disciplinary = true
        where id = v_entry.id;
      else
        insert into public.planning_entries(
          id,date_str,shift_id,owner_id,owner_phone,owner_name,created_at,
          source_type,source_resource_id,source_resource_updated_at,is_disciplinary
        ) values (
          'pdf-' || replace(gen_random_uuid()::text,'-',''),
          v_date,v_shift,v_profile.id,v_profile.phone,
          trim(v_profile.prenom || ' ' || v_profile.nom),now(),
          'official_emergency',p_resource_id,p_resource_updated_at,true
        );
      end if;
    elsif found
       and v_entry.source_type = 'official_emergency'
       and v_entry.source_resource_id = p_resource_id then
      update public.planning_entries
      set is_disciplinary = false
      where id = v_entry.id;
    end if;
  end loop;

  update public.official_roster_import_runs
  set sync_revision = v_revision,
      imported_at = now(),
      imported_by = auth.uid()
  where resource_id = p_resource_id
    and resource_updated_at = p_resource_updated_at;

  return coalesce(v_result, '{}'::jsonb) || jsonb_build_object(
    'disciplinary_revision', v_revision
  );
end;
$$;

create or replace function public.import_official_emergency_roster_for_profile(
  p_resource_id uuid,
  p_resource_updated_at timestamptz,
  p_profile_id uuid,
  p_assignments jsonb,
  p_unmatched_cells jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_resource public.shared_resources%rowtype;
  v_profile public.profiles%rowtype;
  v_entry public.planning_entries%rowtype;
  v_item jsonb;
  v_item_profile_id uuid;
  v_date date;
  v_shift text;
  v_disciplinary boolean;
  v_hospital text;
  v_revision constant text := 'v11.6.47-r1';
begin
  if auth.uid() is null then raise exception 'Session requise'; end if;
  if p_profile_id <> auth.uid() and not public.is_admin() then
    raise exception 'Accès refusé';
  end if;

  select * into v_profile
  from public.profiles
  where id = p_profile_id and account_status = 'active'
  for update;
  if not found then raise exception 'Médecin actif introuvable'; end if;

  select * into v_resource
  from public.shared_resources
  where id = p_resource_id and kind = 'official_pdf'
  for update;
  if not found then raise exception 'Planning officiel introuvable'; end if;
  if v_resource.updated_at is distinct from p_resource_updated_at then
    raise exception 'Le PDF a été remplacé pendant son analyse. Relancer la synchronisation.';
  end if;

  v_hospital := case v_resource.slot
    when 'hm6_bouskoura' then 'Hôpital Universitaire International Mohammed VI de Bouskoura'
    when 'hm6_rabat' then 'Hôpital Universitaire International Mohammed VI de Rabat'
    when 'hck_casa' then 'Hôpital Universitaire International Cheikh Khalifa de Casablanca'
    else null
  end;
  if v_profile.hospital is distinct from v_hospital then
    raise exception 'Le planning officiel ne correspond pas à l’établissement du médecin';
  end if;

  v_result := public.import_official_emergency_roster_for_profile_legacy_v46(
    p_resource_id,
    p_resource_updated_at,
    p_profile_id,
    p_assignments,
    p_unmatched_cells
  );

  perform set_config('gardeflow.official_import', '1', true);

  for v_item in select value from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb))
  loop
    begin
      v_item_profile_id := nullif(v_item->>'profile_id','')::uuid;
      v_date := nullif(v_item->>'date','')::date;
      v_shift := v_item->>'shift_id';
      v_disciplinary := coalesce(nullif(v_item->>'is_disciplinary','')::boolean, false);
    exception when others then
      continue;
    end;

    if v_item_profile_id <> p_profile_id then continue; end if;
    if v_shift not in ('urg-jour','urg-nuit','urg-24h') then continue; end if;

    select * into v_entry
    from public.planning_entries
    where owner_id = p_profile_id
      and date_str = v_date
      and deleted_at is null
    for update;

    -- La synchronisation individuelle peut ajouter le verrou disciplinaire
    -- à une garde déjà reconnue par l'import officiel, mais elle ne peut ni
    -- fabriquer une garde disciplinaire arbitraire ni retirer un verrou existant.
    -- La suppression du marqueur reste réservée à l'import administrateur.
    if v_disciplinary
       and found
       and v_entry.source_type = 'official_emergency'
       and v_entry.source_resource_id = p_resource_id
       and v_entry.shift_id = v_shift
       and not v_entry.is_disciplinary then
      update public.exchange_requests
      set status = 'cancelled'
      where status in ('pendingB','pendingAdmin')
        and (planning_entry_id = v_entry.id or target_planning_entry_id = v_entry.id);

      update public.planning_entries
      set is_disciplinary = true
      where id = v_entry.id;
    end if;
  end loop;

  update public.official_roster_profile_sync
  set sync_revision = v_revision,
      synced_at = now()
  where resource_id = p_resource_id
    and resource_updated_at = p_resource_updated_at
    and profile_id = p_profile_id;

  return coalesce(v_result, '{}'::jsonb) || jsonb_build_object(
    'disciplinary_revision', v_revision
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
  if not public.is_admin() then raise exception 'Réservé à l’administrateur'; end if;
  return exists(
    select 1 from public.official_roster_import_runs r
    where r.resource_id = p_resource_id
      and r.resource_updated_at = p_resource_updated_at
      and r.sync_revision = 'v11.6.47-r1'
  );
end;
$$;

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
  v_revision constant text := 'v11.6.47-r1';
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
    select 1 from public.official_roster_profile_sync s
    where s.resource_id = p_resource_id
      and s.resource_updated_at = p_resource_updated_at
      and s.profile_id = p_profile_id
      and s.profile_signature = v_signature
      and s.sync_revision = v_revision
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Suppression admin : une garde disciplinaire peut être retirée par un admin
-- même si le mois n'est pas encore validé, avec motif et journal d'audit.
-- ---------------------------------------------------------------------------
create or replace function public.admin_delete_planning(p_entry_id text, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  e public.planning_entries%rowtype;
  approved_leave boolean := false;
begin
  if not public.is_admin() then raise exception 'Réservé à l’administrateur'; end if;
  if length(trim(coalesce(p_reason,''))) < 3 then raise exception 'Motif de suppression obligatoire'; end if;

  select * into e
  from public.planning_entries
  where id = p_entry_id and deleted_at is null
  for update;
  if not found then raise exception 'Affectation introuvable'; end if;

  if e.shift_id = 'conge' and e.leave_request_id is not null then
    select exists(
      select 1 from public.leave_requests l
      where l.id = e.leave_request_id and l.status = 'approved'
    ) into approved_leave;
  end if;

  if not e.is_disciplinary
     and not public.planning_month_is_approved(e.owner_id,e.date_str)
     and not approved_leave then
    raise exception 'Seules les affectations validées ou disciplinaires peuvent être supprimées par l’administrateur';
  end if;

  if e.shift_id = 'conge' and e.leave_request_id is not null and not approved_leave then
    raise exception 'Ce congé est encore en attente : utilisez Approuver ou Refuser';
  end if;

  perform set_config('huim6.review_request','1',true);
  if e.is_disciplinary then
    perform set_config('gardeflow.disciplinary_admin_delete','1',true);
  end if;

  update public.exchange_requests
     set status = 'cancelled'
   where status in ('pendingB','pendingAdmin')
     and (planning_entry_id = p_entry_id or target_planning_entry_id = p_entry_id);

  if approved_leave then
    update public.planning_entries
       set deleted_at = now()
     where leave_request_id = e.leave_request_id and deleted_at is null;

    update public.leave_requests
       set status = 'cancelled', reviewed_at = now()
     where id = e.leave_request_id and status = 'approved';
  else
    update public.planning_entries set deleted_at = now() where id = p_entry_id;
  end if;

  perform public.write_audit(
    'planning.deleted','planning_entry',p_entry_id,e.owner_id,e.owner_name,trim(p_reason),
    jsonb_build_object(
      'date',e.date_str,
      'shift_id',e.shift_id,
      'leave_request_id',e.leave_request_id,
      'is_disciplinary',e.is_disciplinary
    )
  );
end;
$$;
