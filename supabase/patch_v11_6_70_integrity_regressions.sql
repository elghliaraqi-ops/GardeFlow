-- GardeFlow V11.6.70 - integrity/security regression fixes
-- Canonical delta from a V11.6.69 database.
-- Idempotent and safe to replay.

begin;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function public.guardeflow_expected_hospital_for_slot(p_slot text)
returns text
language sql
immutable
security invoker
set search_path = public
as $$
  select case p_slot
    when 'hm6_bouskoura' then 'Hôpital Universitaire International Mohammed VI de Bouskoura'
    when 'hm6_rabat' then 'Hôpital Universitaire International Mohammed VI de Rabat'
    when 'hck_casa' then 'Hôpital Universitaire International Cheikh Khalifa de Casablanca'
    else null
  end
$$;

revoke all on function public.guardeflow_expected_hospital_for_slot(text)
  from public, anon, authenticated;

create or replace function public.guardeflow_is_past_month(p_date date)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select date_trunc('month', p_date)::date
       < date_trunc('month', current_date)::date
$$;

revoke all on function public.guardeflow_is_past_month(date) from public, anon;
grant execute on function public.guardeflow_is_past_month(date)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Pending accounts: no official PDFs/shared storage.
-- ---------------------------------------------------------------------------

drop policy if exists shared_resources_read on public.shared_resources;
create policy shared_resources_read
on public.shared_resources
for select
to authenticated
using (public.current_account_active());

drop policy if exists gardeflow_shared_read on storage.objects;
create policy gardeflow_shared_read
on storage.objects
for select
to authenticated
using (
  bucket_id = 'gardeflow-shared'
  and public.current_account_active()
);

-- ---------------------------------------------------------------------------
-- Past months: human/API sessions are immutable. service_role is maintenance
-- only (e.g. hard account deletion) and may clean historical rows.
-- ---------------------------------------------------------------------------

drop trigger if exists protect_past_planning_entries_trigger
  on public.planning_entries;
drop trigger if exists protect_past_month_planning_entry_trigger
  on public.planning_entries;

create or replace function public.protect_past_month_planning_entry()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_old_past boolean := false;
  v_new_past boolean := false;
  v_service_role boolean :=
    coalesce(auth.jwt()->>'role','') = 'service_role';
begin
  if v_service_role then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;

  if tg_op <> 'INSERT' then
    v_old_past := public.guardeflow_is_past_month(old.date_str);
  end if;
  if tg_op <> 'DELETE' then
    v_new_past := public.guardeflow_is_past_month(new.date_str);
  end if;

  if v_old_past or v_new_past then
    raise exception
      'Mois passé : le planning est en lecture seule et ne peut plus être modifié.';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function public.protect_past_month_planning_entry()
  from public, anon, authenticated;

create trigger protect_past_month_planning_entry_trigger
before insert or update or delete on public.planning_entries
for each row execute function public.protect_past_month_planning_entry();


create or replace function public.protect_past_planning_month()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_year integer;
  v_month integer;
  v_first_day date;
begin
  if coalesce(auth.jwt()->>'role','') = 'service_role' then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;

  if tg_op = 'DELETE' then
    v_year := old.year;
    v_month := old.month;
  else
    v_year := new.year;
    v_month := new.month;
  end if;

  v_first_day := make_date(v_year, v_month, 1);
  if v_first_day < date_trunc('month', current_date)::date then
    raise exception
      'Mois passé : le calendrier est en lecture seule et ne peut plus être modifié.';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function public.protect_past_planning_month()
  from public, anon, authenticated;

drop trigger if exists protect_past_planning_month_trigger
  on public.planning_months;

create trigger protect_past_planning_month_trigger
before insert or update or delete on public.planning_months
for each row execute function public.protect_past_planning_month();


-- ---------------------------------------------------------------------------
-- Disciplinary guards: trusted service cleanup is allowed; normal doctors,
-- admins and official-import paths keep their existing rules.
-- ---------------------------------------------------------------------------

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
  if coalesce(auth.jwt()->>'role','') = 'service_role' then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;

  if tg_op = 'INSERT' then
    v_new_disc := public.is_current_disciplinary_guard(new.owner_id, new.date_str);

    if v_new_disc then
      if coalesce(current_setting('gardeflow.official_import', true), '0') = '1' then
        new.is_disciplinary := true;
        return new;
      end if;

      raise exception
        'Garde disciplinaire : cette date est verrouillée. Seul un administrateur peut la supprimer.';
    end if;

    return new;
  end if;

  v_old_disc := old.is_disciplinary
    or public.is_current_disciplinary_guard(old.owner_id, old.date_str);

  if tg_op = 'DELETE' then
    if not v_old_disc then return old; end if;

    if coalesce(current_setting('gardeflow.official_import', true), '0') = '1' then
      return old;
    end if;

    if coalesce(current_setting('gardeflow.disciplinary_admin_delete', true), '0') = '1'
       and public.is_admin() then
      return old;
    end if;

    raise exception
      'Garde disciplinaire : suppression réservée à l’administrateur.';
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

    raise exception
      'Garde disciplinaire : annulation, modification et échange interdits. Seul un administrateur peut la supprimer.';
  end if;

  if v_new_disc then
    new.is_disciplinary := true;
  end if;

  return new;
end;
$$;

revoke execute on function public.protect_disciplinary_guard()
  from public, anon, authenticated;


-- ---------------------------------------------------------------------------
-- Manual planning: started guards and absurd future dates are rejected.
-- UI horizon is current year + 2 through 31 December.
-- ---------------------------------------------------------------------------

create or replace function public.save_my_planning_entry(
  p_date date,
  p_shift_id text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  me public.profiles%rowtype;
  month_state text;
  existing public.planning_entries%rowtype;
  entry_id text;
  y int := extract(year from p_date)::int;
  m int := extract(month from p_date)::int;
  max_date date :=
    make_date(extract(year from current_date)::int + 2, 12, 31);
begin
  select * into me
  from public.profiles
  where id=auth.uid() and account_status='active';

  if not found then raise exception 'Compte actif requis'; end if;
  if p_date < current_date then
    raise exception 'Une date passée ne peut plus être modifiée';
  end if;

  if p_shift_id not in (
    'service-jour','service-24h','service-nuit',
    'urg-jour','urg-24h','urg-nuit','conge'
  ) then
    raise exception 'Type de tuile invalide';
  end if;

  if p_date > max_date then
    raise exception
      'Cette date dépasse l’horizon de planification autorisé';
  end if;

  if p_shift_id <> 'conge'
     and public.guard_has_started(p_date, p_shift_id) then
    raise exception
      'Cette garde a déjà commencé et ne peut plus être ajoutée ou modifiée';
  end if;

  select status into month_state
  from public.planning_months
  where owner_id=me.id and year=y and month=m
  for update;

  if month_state='approved' then
    raise exception
      'Calendrier validé définitivement : aucune modification directe n’est possible';
  end if;

  insert into public.planning_months(owner_id,year,month,status,updated_at)
  values(me.id,y,m,'draft',now())
  on conflict(owner_id,year,month) do update
    set status='draft',
        submitted_at=null,
        reviewed_at=null,
        reviewed_by=null,
        rejection_reason=null,
        updated_at=now()
    where public.planning_months.status<>'approved';

  select * into existing
  from public.planning_entries
  where owner_id=me.id and date_str=p_date and deleted_at is null
  for update;

  if found then
    if existing.shift_id='conge'
       and existing.leave_request_id is not null
       and exists(
         select 1
         from public.leave_requests l
         where l.id=existing.leave_request_id
           and l.status='approved'
       ) then
      raise exception
        'Ce congé a déjà été approuvé : seul un administrateur peut le supprimer';
    end if;

    if exists(
      select 1
      from public.exchange_requests r
      where r.status in ('pendingB','pendingAdmin')
        and (
          r.planning_entry_id=existing.id
          or r.target_planning_entry_id=existing.id
        )
    ) then
      raise exception 'Cette garde est verrouillée par une demande active';
    end if;

    update public.planning_entries
       set shift_id=p_shift_id,
           owner_phone=me.phone,
           owner_name=trim(me.prenom||' '||me.nom),
           leave_request_id=null
     where id=existing.id;
    entry_id:=existing.id;
  else
    entry_id:='p-'||replace(gen_random_uuid()::text,'-','');
    insert into public.planning_entries(
      id,date_str,shift_id,owner_id,owner_phone,owner_name,created_at
    ) values (
      entry_id,p_date,p_shift_id,me.id,me.phone,
      trim(me.prenom||' '||me.nom),now()
    );
  end if;

  return entry_id;
end;
$$;

revoke execute on function public.save_my_planning_entry(date,text)
  from public, anon;
grant execute on function public.save_my_planning_entry(date,text)
  to authenticated, service_role;


-- ---------------------------------------------------------------------------
-- Official PDF imports: past entries are preserved and omitted from every
-- mutation attempt. This prevents a replacement PDF from aborting because
-- historical rows are read-only.
-- ---------------------------------------------------------------------------

create or replace function public.import_official_emergency_roster(
  p_resource_id uuid,
  p_resource_updated_at timestamp with time zone,
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
  v_safe_assignments jsonb := '[]'::jsonb;
  v_safe_unmatched jsonb := '[]'::jsonb;
  v_past_cells jsonb := '[]'::jsonb;
  v_revision constant text := 'v11.6.70-r1';
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;

  select * into v_resource
  from public.shared_resources
  where id=p_resource_id and kind='official_pdf'
  for update;

  if not found then raise exception 'Planning officiel introuvable'; end if;
  if v_resource.updated_at is distinct from p_resource_updated_at then
    raise exception
      'Le PDF a été remplacé pendant son analyse. Relancer la synchronisation.';
  end if;

  v_hospital := public.guardeflow_expected_hospital_for_slot(v_resource.slot);
  if v_hospital is null then
    raise exception 'Établissement du PDF invalide';
  end if;

  if jsonb_typeof(coalesce(p_unmatched_cells,'[]'::jsonb))='array' then
    v_safe_unmatched := coalesce(p_unmatched_cells,'[]'::jsonb);
  end if;

  for v_item in
    select value
    from jsonb_array_elements(coalesce(p_assignments,'[]'::jsonb))
  loop
    begin
      v_date := nullif(v_item->>'date','')::date;
    exception when others then
      v_safe_assignments :=
        v_safe_assignments || jsonb_build_array(v_item);
      continue;
    end;

    if v_date is null or not public.guardeflow_is_past_month(v_date) then
      v_safe_assignments :=
        v_safe_assignments || jsonb_build_array(v_item);
    end if;
  end loop;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'date', e.date_str::text,
        'reason', 'past_month_protected'
      )
    ),
    '[]'::jsonb
  )
  into v_past_cells
  from public.planning_entries e
  where e.source_type='official_emergency'
    and e.source_resource_id=p_resource_id
    and e.deleted_at is null
    and public.guardeflow_is_past_month(e.date_str);

  v_safe_unmatched := v_safe_unmatched || v_past_cells;

  v_result := public.import_official_emergency_roster_legacy_v46(
    p_resource_id,
    p_resource_updated_at,
    v_safe_assignments,
    v_safe_unmatched
  );

  perform set_config('gardeflow.official_import','1',true);

  for v_item in
    select value
    from jsonb_array_elements(v_safe_assignments)
  loop
    begin
      v_profile_id := nullif(v_item->>'profile_id','')::uuid;
      v_date := nullif(v_item->>'date','')::date;
      v_shift := v_item->>'shift_id';
      v_disciplinary :=
        coalesce(nullif(v_item->>'is_disciplinary','')::boolean,false);
    exception when others then
      continue;
    end;

    if v_date is null
       or public.guardeflow_is_past_month(v_date)
       or v_shift not in ('urg-jour','urg-nuit','urg-24h') then
      continue;
    end if;

    select * into v_profile
    from public.profiles
    where id=v_profile_id
      and account_status='active'
      and hospital=v_hospital;

    if not found then continue; end if;

    select * into v_entry
    from public.planning_entries
    where owner_id=v_profile_id
      and date_str=v_date
      and deleted_at is null
    for update;

    if v_disciplinary then
      if found then
        update public.exchange_requests
        set status='cancelled'
        where status in ('pendingB','pendingAdmin')
          and (
            planning_entry_id=v_entry.id
            or target_planning_entry_id=v_entry.id
          );

        update public.planning_entries
        set shift_id=v_shift,
            owner_phone=v_profile.phone,
            owner_name=trim(v_profile.prenom||' '||v_profile.nom),
            leave_request_id=null,
            source_type='official_emergency',
            source_resource_id=p_resource_id,
            source_resource_updated_at=p_resource_updated_at,
            is_disciplinary=true
        where id=v_entry.id;
      else
        insert into public.planning_entries(
          id,date_str,shift_id,owner_id,owner_phone,owner_name,created_at,
          source_type,source_resource_id,source_resource_updated_at,
          is_disciplinary
        ) values (
          'pdf-'||replace(gen_random_uuid()::text,'-',''),
          v_date,v_shift,v_profile.id,v_profile.phone,
          trim(v_profile.prenom||' '||v_profile.nom),now(),
          'official_emergency',p_resource_id,p_resource_updated_at,true
        );
      end if;
    elsif found
       and v_entry.source_type='official_emergency'
       and v_entry.source_resource_id=p_resource_id then
      update public.planning_entries
      set is_disciplinary=false
      where id=v_entry.id;
    end if;
  end loop;

  update public.official_roster_import_runs
  set sync_revision=v_revision,
      imported_at=now(),
      imported_by=auth.uid()
  where resource_id=p_resource_id
    and resource_updated_at=p_resource_updated_at;

  return coalesce(v_result,'{}'::jsonb)
    || jsonb_build_object('disciplinary_revision',v_revision);
end;
$$;

revoke execute on function public.import_official_emergency_roster(
  uuid,timestamp with time zone,jsonb,jsonb
) from public, anon;
grant execute on function public.import_official_emergency_roster(
  uuid,timestamp with time zone,jsonb,jsonb
) to authenticated, service_role;


create or replace function public.import_official_emergency_roster_for_profile(
  p_resource_id uuid,
  p_resource_updated_at timestamp with time zone,
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
  v_safe_assignments jsonb := '[]'::jsonb;
  v_safe_unmatched jsonb := '[]'::jsonb;
  v_past_cells jsonb := '[]'::jsonb;
  v_revision constant text := 'v11.6.70-r1';
begin
  if auth.uid() is null then raise exception 'Session requise'; end if;
  if p_profile_id <> auth.uid() and not public.is_admin() then
    raise exception 'Accès refusé';
  end if;

  select * into v_profile
  from public.profiles
  where id=p_profile_id and account_status='active'
  for update;

  if not found then raise exception 'Médecin actif introuvable'; end if;

  select * into v_resource
  from public.shared_resources
  where id=p_resource_id and kind='official_pdf'
  for update;

  if not found then raise exception 'Planning officiel introuvable'; end if;
  if v_resource.updated_at is distinct from p_resource_updated_at then
    raise exception
      'Le PDF a été remplacé pendant son analyse. Relancer la synchronisation.';
  end if;

  v_hospital := public.guardeflow_expected_hospital_for_slot(v_resource.slot);
  if v_hospital is null
     or v_profile.hospital is distinct from v_hospital then
    raise exception
      'Le planning officiel ne correspond pas à l’établissement du médecin';
  end if;

  if jsonb_typeof(coalesce(p_unmatched_cells,'[]'::jsonb))='array' then
    v_safe_unmatched := coalesce(p_unmatched_cells,'[]'::jsonb);
  end if;

  for v_item in
    select value
    from jsonb_array_elements(coalesce(p_assignments,'[]'::jsonb))
  loop
    begin
      v_date := nullif(v_item->>'date','')::date;
    exception when others then
      v_safe_assignments :=
        v_safe_assignments || jsonb_build_array(v_item);
      continue;
    end;

    if v_date is null or not public.guardeflow_is_past_month(v_date) then
      v_safe_assignments :=
        v_safe_assignments || jsonb_build_array(v_item);
    end if;
  end loop;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'date', e.date_str::text,
        'reason', 'past_month_protected'
      )
    ),
    '[]'::jsonb
  )
  into v_past_cells
  from public.planning_entries e
  where e.owner_id=p_profile_id
    and e.source_type='official_emergency'
    and e.source_resource_id=p_resource_id
    and e.deleted_at is null
    and public.guardeflow_is_past_month(e.date_str);

  v_safe_unmatched := v_safe_unmatched || v_past_cells;

  v_result := public.import_official_emergency_roster_for_profile_legacy_v46(
    p_resource_id,
    p_resource_updated_at,
    p_profile_id,
    v_safe_assignments,
    v_safe_unmatched
  );

  perform set_config('gardeflow.official_import','1',true);

  for v_item in
    select value
    from jsonb_array_elements(v_safe_assignments)
  loop
    begin
      v_item_profile_id := nullif(v_item->>'profile_id','')::uuid;
      v_date := nullif(v_item->>'date','')::date;
      v_shift := v_item->>'shift_id';
      v_disciplinary :=
        coalesce(nullif(v_item->>'is_disciplinary','')::boolean,false);
    exception when others then
      continue;
    end;

    if v_item_profile_id <> p_profile_id
       or v_date is null
       or public.guardeflow_is_past_month(v_date)
       or v_shift not in ('urg-jour','urg-nuit','urg-24h') then
      continue;
    end if;

    select * into v_entry
    from public.planning_entries
    where owner_id=p_profile_id
      and date_str=v_date
      and deleted_at is null
    for update;

    if v_disciplinary
       and found
       and v_entry.source_type='official_emergency'
       and v_entry.source_resource_id=p_resource_id
       and v_entry.shift_id=v_shift
       and not v_entry.is_disciplinary then
      update public.exchange_requests
      set status='cancelled'
      where status in ('pendingB','pendingAdmin')
        and (
          planning_entry_id=v_entry.id
          or target_planning_entry_id=v_entry.id
        );

      update public.planning_entries
      set is_disciplinary=true
      where id=v_entry.id;
    end if;
  end loop;

  update public.official_roster_profile_sync
  set sync_revision=v_revision,
      synced_at=now()
  where resource_id=p_resource_id
    and resource_updated_at=p_resource_updated_at
    and profile_id=p_profile_id;

  return coalesce(v_result,'{}'::jsonb)
    || jsonb_build_object('disciplinary_revision',v_revision);
end;
$$;

revoke execute on function public.import_official_emergency_roster_for_profile(
  uuid,timestamp with time zone,uuid,jsonb,jsonb
) from public, anon;
grant execute on function public.import_official_emergency_roster_for_profile(
  uuid,timestamp with time zone,uuid,jsonb,jsonb
) to authenticated, service_role;


-- ---------------------------------------------------------------------------
-- Disciplinary marks: never match a same-name doctor from another hospital,
-- and never mutate historical planning.
-- ---------------------------------------------------------------------------

create or replace function public.register_official_disciplinary_marks(
  p_resource_id uuid,
  p_resource_updated_at timestamp with time zone,
  p_marks jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  resource_row public.shared_resources%rowtype;
  mark jsonb;
  mark_date date;
  mark_shift text;
  mark_text text;
  mark_norm text;
  v_hospital text;
  matched_count int := 0;
  rule_count int := 0;
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;

  select * into resource_row
  from public.shared_resources
  where id=p_resource_id and kind='official_pdf'
  for update;

  if not found then raise exception 'Planning officiel introuvable'; end if;
  if resource_row.updated_at is distinct from p_resource_updated_at then
    raise exception 'Le PDF a été remplacé pendant son analyse.';
  end if;

  v_hospital :=
    public.guardeflow_expected_hospital_for_slot(resource_row.slot);

  if v_hospital is null then
    raise exception 'Établissement du PDF invalide';
  end if;

  delete from public.official_disciplinary_name_rules
  where resource_id=p_resource_id
    and resource_updated_at=p_resource_updated_at;

  for mark in
    select value
    from jsonb_array_elements(coalesce(p_marks,'[]'::jsonb))
  loop
    begin
      mark_date := nullif(mark->>'date','')::date;
      mark_shift := mark->>'shift_id';
      mark_text := trim(coalesce(mark->>'red_text',''));
      mark_norm := public.normalize_doctor_text(mark_text);
    exception when others then
      continue;
    end;

    if mark_date is null
       or mark_shift not in ('urg-jour','urg-nuit','urg-24h')
       or mark_norm='' then
      continue;
    end if;

    insert into public.official_disciplinary_name_rules(
      resource_id,resource_updated_at,date_str,shift_id,
      red_text,normalized_red_text,detected_at
    )
    values(
      p_resource_id,p_resource_updated_at,mark_date,mark_shift,
      mark_text,mark_norm,now()
    )
    on conflict(
      resource_id,resource_updated_at,date_str,shift_id,normalized_red_text
    )
    do update
      set red_text=excluded.red_text,
          detected_at=now();

    rule_count := rule_count + 1;
  end loop;

  perform set_config('gardeflow.official_import','1',true);

  -- Remove any non-historical cross-hospital registry rows produced by an
  -- earlier vulnerable revision. Historical planning itself is not touched.
  delete from public.official_disciplinary_guards g
  using public.profiles p
  where g.owner_id=p.id
    and g.resource_id=p_resource_id
    and g.resource_updated_at=p_resource_updated_at
    and p.hospital is distinct from v_hospital
    and not public.guardeflow_is_past_month(g.date_str);

  with matches as (
    select
      p.id as owner_id,
      r.date_str,
      r.shift_id,
      r.resource_id,
      r.resource_updated_at
    from public.profiles p
    join public.official_disciplinary_name_rules r
      on r.resource_id=p_resource_id
     and r.resource_updated_at=p_resource_updated_at
    where p.account_status='active'
      and p.hospital=v_hospital
      and not public.guardeflow_is_past_month(r.date_str)
      and public.profile_matches_disciplinary_rule(
        p.id,r.date_str,r.normalized_red_text
      )
  )
  insert into public.official_disciplinary_guards(
    owner_id,date_str,shift_id,resource_id,resource_updated_at,detected_at
  )
  select owner_id,date_str,shift_id,resource_id,resource_updated_at,now()
  from matches
  on conflict(owner_id,date_str,resource_id,resource_updated_at)
  do update
    set shift_id=excluded.shift_id,
        detected_at=now();

  with matches as (
    select
      p.id as owner_id,
      r.date_str,
      r.shift_id,
      r.resource_id,
      r.resource_updated_at
    from public.profiles p
    join public.official_disciplinary_name_rules r
      on r.resource_id=p_resource_id
     and r.resource_updated_at=p_resource_updated_at
    where p.account_status='active'
      and p.hospital=v_hospital
      and not public.guardeflow_is_past_month(r.date_str)
      and public.profile_matches_disciplinary_rule(
        p.id,r.date_str,r.normalized_red_text
      )
  )
  update public.planning_entries e
  set is_disciplinary=true,
      shift_id=m.shift_id,
      source_type='official_emergency',
      source_resource_id=m.resource_id,
      source_resource_updated_at=m.resource_updated_at
  from matches m
  where e.owner_id=m.owner_id
    and e.date_str=m.date_str
    and e.deleted_at is null;

  get diagnostics matched_count = row_count;

  update public.official_roster_import_runs
  set sync_revision='v11.6.70-r1',
      imported_at=now(),
      imported_by=auth.uid()
  where resource_id=p_resource_id
    and resource_updated_at=p_resource_updated_at;

  return jsonb_build_object(
    'rules',rule_count,
    'active_entries_locked',matched_count,
    'revision','v11.6.70-r1'
  );
end;
$$;

revoke execute on function public.register_official_disciplinary_marks(
  uuid,timestamp with time zone,jsonb
) from public, anon;
grant execute on function public.register_official_disciplinary_marks(
  uuid,timestamp with time zone,jsonb
) to authenticated, service_role;

commit;
