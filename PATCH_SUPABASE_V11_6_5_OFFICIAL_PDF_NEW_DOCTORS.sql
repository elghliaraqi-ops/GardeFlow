-- GardeFlow V11.6.5
-- Correction : un médecin créé/validé APRES l'import initial d'un PDF officiel
-- récupère automatiquement ses gardes Urgences depuis le PDF déjà publié.
-- Compatible HUIM6 Bouskoura / HUIM6 Rabat / HUICK Casa.
-- À exécuter dans Supabase > SQL Editor avant d'installer V11.6.5.

create table if not exists public.official_roster_profile_sync (
  resource_id uuid not null references public.shared_resources(id) on delete cascade,
  resource_updated_at timestamptz not null,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  profile_signature text not null,
  sync_revision text not null default 'v11.6.5-r1',
  synced_at timestamptz not null default now(),
  assignment_count integer not null default 0,
  inserted_count integer not null default 0,
  updated_count integer not null default 0,
  removed_count integer not null default 0,
  skipped_manual_count integer not null default 0,
  skipped_locked_count integer not null default 0,
  invalid_count integer not null default 0,
  unmatched_cells jsonb not null default '[]'::jsonb,
  primary key(resource_id, resource_updated_at, profile_id)
);

alter table public.official_roster_profile_sync
  add column if not exists sync_revision text not null default 'v11.6.5-r1';
alter table public.official_roster_profile_sync
  add column if not exists skipped_locked_count integer not null default 0;

create index if not exists official_roster_profile_sync_profile_idx
  on public.official_roster_profile_sync(profile_id, synced_at desc);

alter table public.official_roster_profile_sync enable row level security;

drop policy if exists official_roster_profile_sync_read
  on public.official_roster_profile_sync;
create policy official_roster_profile_sync_read
on public.official_roster_profile_sync
for select
to authenticated
using (profile_id = auth.uid() or public.is_admin());

grant select on public.official_roster_profile_sync to authenticated;
revoke insert, update, delete on public.official_roster_profile_sync from authenticated;

create or replace function public.official_roster_profile_sync_is_current(
  p_resource_id uuid,
  p_resource_updated_at timestamptz,
  p_profile_id uuid
)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles%rowtype;
  v_signature text;
  v_revision constant text := 'v11.6.5-r1';
begin
  if auth.uid() is null then raise exception 'Session requise'; end if;
  if p_profile_id <> auth.uid() and not public.is_admin() then raise exception 'Accès refusé'; end if;

  select * into v_profile
  from public.profiles p
  where p.id=p_profile_id and p.account_status='active';
  if not found then return false; end if;

  v_signature := md5(
    lower(trim(coalesce(v_profile.prenom,''))) || '|' ||
    lower(trim(coalesce(v_profile.nom,''))) || '|' ||
    coalesce(v_profile.phone,'') || '|' ||
    coalesce(v_profile.hospital,'') || '|' ||
    coalesce(v_profile.account_status,'')
  );

  return exists(
    select 1
    from public.official_roster_profile_sync s
    where s.resource_id=p_resource_id
      and s.resource_updated_at=p_resource_updated_at
      and s.profile_id=p_profile_id
      and s.profile_signature=v_signature
      and s.sync_revision=v_revision
  );
end;
$$;

revoke all on function public.official_roster_profile_sync_is_current(uuid,timestamptz,uuid)
  from public,anon;
grant execute on function public.official_roster_profile_sync_is_current(uuid,timestamptz,uuid)
  to authenticated;

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
set search_path=public
as $$
declare
  v_resource public.shared_resources%rowtype;
  v_profile public.profiles%rowtype;
  v_existing public.planning_entries%rowtype;
  v_hospital text;
  v_signature text;
  v_revision constant text := 'v11.6.5-r1';
  v_item jsonb;
  v_item_profile_id uuid;
  v_date date;
  v_shift text;
  v_month_status text;
  v_inserted int:=0;
  v_updated int:=0;
  v_removed int:=0;
  v_skipped_manual int:=0;
  v_skipped_locked int:=0;
  v_invalid int:=0;
  v_assignment_count int:=0;
begin
  if auth.uid() is null then raise exception 'Session requise'; end if;
  if p_profile_id <> auth.uid() and not public.is_admin() then raise exception 'Accès refusé'; end if;

  if jsonb_typeof(coalesce(p_assignments,'[]'::jsonb)) <> 'array' then
    raise exception 'Affectations invalides';
  end if;
  if jsonb_typeof(coalesce(p_unmatched_cells,'[]'::jsonb)) <> 'array' then
    p_unmatched_cells:='[]'::jsonb;
  end if;

  select * into v_profile
  from public.profiles p
  where p.id=p_profile_id and p.account_status='active'
  for update;
  if not found then raise exception 'Médecin actif introuvable'; end if;

  select * into v_resource
  from public.shared_resources r
  where r.id=p_resource_id and r.kind='official_pdf'
  for update;
  if not found then raise exception 'Planning officiel introuvable'; end if;
  if v_resource.updated_at is distinct from p_resource_updated_at then
    raise exception 'Le PDF a été remplacé pendant son analyse. Relancer la synchronisation.';
  end if;

  v_hospital:=case v_resource.slot
    when 'hm6_bouskoura' then 'Hôpital Universitaire International Mohammed VI de Bouskoura'
    when 'hm6_rabat' then 'Hôpital Universitaire International Mohammed VI de Rabat'
    when 'hck_casa' then 'Hôpital Universitaire International Cheikh Khalifa de Casablanca'
    else null
  end;
  if v_hospital is null then raise exception 'Établissement du PDF invalide'; end if;
  if v_profile.hospital <> v_hospital then
    raise exception 'Le planning officiel ne correspond pas à l’établissement du médecin';
  end if;

  v_signature := md5(
    lower(trim(coalesce(v_profile.prenom,''))) || '|' ||
    lower(trim(coalesce(v_profile.nom,''))) || '|' ||
    coalesce(v_profile.phone,'') || '|' ||
    coalesce(v_profile.hospital,'') || '|' ||
    coalesce(v_profile.account_status,'')
  );

  if exists(
    select 1 from public.official_roster_profile_sync s
    where s.resource_id=p_resource_id
      and s.resource_updated_at=p_resource_updated_at
      and s.profile_id=p_profile_id
      and s.profile_signature=v_signature
      and s.sync_revision=v_revision
  ) then
    return jsonb_build_object('already_processed',true,'inserted',0,'updated',0,'removed',0,'skipped_manual',0,'skipped_locked',0,'invalid',0);
  end if;

  perform set_config('gardeflow.official_import','1',true);

  for v_existing in
    select e.*
    from public.planning_entries e
    where e.owner_id=p_profile_id
      and e.source_type='official_emergency'
      and e.source_resource_id=p_resource_id
      and e.deleted_at is null
      and not exists (
        select 1 from jsonb_array_elements(coalesce(p_assignments,'[]'::jsonb)) a
        where nullif(a->>'profile_id','')::uuid=p_profile_id
          and nullif(a->>'date','')::date=e.date_str
      )
      and not exists (
        select 1 from jsonb_array_elements(coalesce(p_unmatched_cells,'[]'::jsonb)) u
        where nullif(u->>'date','')::date=e.date_str
      )
    for update
  loop
    v_month_status:=null;
    select pm.status into v_month_status
    from public.planning_months pm
    where pm.owner_id=p_profile_id
      and pm.year=extract(year from v_existing.date_str)::int
      and pm.month=extract(month from v_existing.date_str)::int;

    if v_month_status in ('submitted','approved') then
      v_skipped_locked:=v_skipped_locked+1;
      continue;
    end if;
    if exists(
      select 1 from public.exchange_requests r
      where r.status in ('pendingB','pendingAdmin')
        and (r.planning_entry_id=v_existing.id or r.target_planning_entry_id=v_existing.id)
    ) then
      v_skipped_manual:=v_skipped_manual+1;
      continue;
    end if;

    update public.planning_entries set deleted_at=now() where id=v_existing.id;
    v_removed:=v_removed+1;
  end loop;

  for v_item in select value from jsonb_array_elements(coalesce(p_assignments,'[]'::jsonb))
  loop
    begin
      v_item_profile_id:=nullif(v_item->>'profile_id','')::uuid;
      v_date:=nullif(v_item->>'date','')::date;
      v_shift:=v_item->>'shift_id';
    exception when others then
      v_invalid:=v_invalid+1;
      continue;
    end;

    if v_item_profile_id <> p_profile_id then v_invalid:=v_invalid+1; continue; end if;
    if v_shift not in ('urg-jour','urg-nuit','urg-24h') then v_invalid:=v_invalid+1; continue; end if;
    v_assignment_count:=v_assignment_count+1;

    v_month_status:=null;
    select pm.status into v_month_status
    from public.planning_months pm
    where pm.owner_id=p_profile_id
      and pm.year=extract(year from v_date)::int
      and pm.month=extract(month from v_date)::int;

    if v_month_status in ('submitted','approved') then
      v_skipped_locked:=v_skipped_locked+1;
      continue;
    end if;

    insert into public.planning_months(owner_id,year,month,status,updated_at)
    values(p_profile_id,extract(year from v_date)::int,extract(month from v_date)::int,'draft',now())
    on conflict(owner_id,year,month) do update
      set status='draft',submitted_at=null,reviewed_at=null,reviewed_by=null,rejection_reason=null,updated_at=now()
      where public.planning_months.status='rejected';

    select * into v_existing
    from public.planning_entries e
    where e.owner_id=p_profile_id and e.date_str=v_date and e.deleted_at is null
    for update;

    if found then
      if v_existing.source_type='official_emergency' and v_existing.source_resource_id=p_resource_id then
        if exists(
          select 1 from public.exchange_requests r
          where r.status in ('pendingB','pendingAdmin')
            and (r.planning_entry_id=v_existing.id or r.target_planning_entry_id=v_existing.id)
        ) then
          v_skipped_manual:=v_skipped_manual+1;
          continue;
        end if;
        update public.planning_entries
        set shift_id=v_shift,
            owner_phone=v_profile.phone,
            owner_name=trim(v_profile.prenom||' '||v_profile.nom),
            leave_request_id=null,
            source_type='official_emergency',
            source_resource_id=p_resource_id,
            source_resource_updated_at=p_resource_updated_at
        where id=v_existing.id;
        v_updated:=v_updated+1;
      else
        v_skipped_manual:=v_skipped_manual+1;
      end if;
    else
      insert into public.planning_entries(
        id,date_str,shift_id,owner_id,owner_phone,owner_name,created_at,
        source_type,source_resource_id,source_resource_updated_at
      ) values (
        'pdf-'||replace(gen_random_uuid()::text,'-',''),v_date,v_shift,p_profile_id,v_profile.phone,
        trim(v_profile.prenom||' '||v_profile.nom),now(),'official_emergency',p_resource_id,p_resource_updated_at
      );
      v_inserted:=v_inserted+1;
    end if;
  end loop;

  insert into public.official_roster_profile_sync(
    resource_id,resource_updated_at,profile_id,profile_signature,sync_revision,synced_at,
    assignment_count,inserted_count,updated_count,removed_count,
    skipped_manual_count,skipped_locked_count,invalid_count,unmatched_cells
  ) values (
    p_resource_id,p_resource_updated_at,p_profile_id,v_signature,v_revision,now(),
    v_assignment_count,v_inserted,v_updated,v_removed,v_skipped_manual,v_skipped_locked,v_invalid,
    coalesce(p_unmatched_cells,'[]'::jsonb)
  )
  on conflict(resource_id,resource_updated_at,profile_id) do update
    set profile_signature=excluded.profile_signature,
        sync_revision=excluded.sync_revision,
        synced_at=excluded.synced_at,
        assignment_count=excluded.assignment_count,
        inserted_count=excluded.inserted_count,
        updated_count=excluded.updated_count,
        removed_count=excluded.removed_count,
        skipped_manual_count=excluded.skipped_manual_count,
        skipped_locked_count=excluded.skipped_locked_count,
        invalid_count=excluded.invalid_count,
        unmatched_cells=excluded.unmatched_cells;

  return jsonb_build_object(
    'already_processed',false,'inserted',v_inserted,'updated',v_updated,'removed',v_removed,
    'skipped_manual',v_skipped_manual,'skipped_locked',v_skipped_locked,'invalid',v_invalid,
    'assignments',v_assignment_count
  );
end;
$$;

revoke all on function public.import_official_emergency_roster_for_profile(uuid,timestamptz,uuid,jsonb,jsonb)
  from public,anon;
grant execute on function public.import_official_emergency_roster_for_profile(uuid,timestamptz,uuid,jsonb,jsonb)
  to authenticated;

-- Vérification facultative :
-- select p.prenom,p.nom,r.slot,s.synced_at,s.assignment_count,s.inserted_count,s.updated_count
-- from public.official_roster_profile_sync s
-- join public.profiles p on p.id=s.profile_id
-- join public.shared_resources r on r.id=s.resource_id
-- order by s.synced_at desc;
