-- GardeFlow V11.6.0
-- Transposition automatique des gardes Urgences depuis les PDF officiels.
-- À exécuter UNE FOIS dans Supabase > SQL Editor avant d'utiliser V11.6.0.
--
-- Le PDF est lu côté application avec pdfrx (texte + coordonnées), puis ce RPC
-- applique les gardes détectées en sécurité côté serveur. Aucun compte médecin
-- ne peut importer des gardes pour un autre utilisateur : appel réservé admin.

-- ---------------------------------------------------------------------------
-- 1) Traçabilité des gardes provenant d'un planning officiel
-- ---------------------------------------------------------------------------
alter table public.planning_entries
  add column if not exists source_type text;
alter table public.planning_entries
  add column if not exists source_resource_id uuid;
alter table public.planning_entries
  add column if not exists source_resource_updated_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='planning_entries_source_resource_id_fkey'
      and conrelid='public.planning_entries'::regclass
  ) then
    alter table public.planning_entries
      add constraint planning_entries_source_resource_id_fkey
      foreign key(source_resource_id)
      references public.shared_resources(id)
      on delete set null;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='planning_entries_source_type_check'
      and conrelid='public.planning_entries'::regclass
  ) then
    alter table public.planning_entries
      add constraint planning_entries_source_type_check
      check (source_type is null or source_type='official_emergency');
  end if;
end $$;

create index if not exists planning_official_source_idx
  on public.planning_entries(source_resource_id, source_resource_updated_at)
  where source_type='official_emergency';

-- Si le médecin modifie lui-même une garde importée avant validation, elle
-- devient une garde manuelle. Un futur rafraîchissement du même PDF ne doit
-- donc pas annuler sa correction.
create or replace function public.detach_official_source_on_owner_edit()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if old.source_type='official_emergency'
     and coalesce(current_setting('gardeflow.official_import',true),'0')<>'1'
     and auth.uid()=old.owner_id
     and (
       new.shift_id is distinct from old.shift_id
       or new.date_str is distinct from old.date_str
       or new.deleted_at is distinct from old.deleted_at
     ) then
    new.source_type:=null;
    new.source_resource_id:=null;
    new.source_resource_updated_at:=null;
  end if;
  return new;
end;
$$;

drop trigger if exists detach_official_source_on_owner_edit_trigger
  on public.planning_entries;
create trigger detach_official_source_on_owner_edit_trigger
before update on public.planning_entries
for each row execute procedure public.detach_official_source_on_owner_edit();

-- ---------------------------------------------------------------------------
-- 2) Historique des versions PDF déjà transposées
-- ---------------------------------------------------------------------------
create table if not exists public.official_roster_import_runs (
  resource_id uuid not null references public.shared_resources(id) on delete cascade,
  resource_updated_at timestamptz not null,
  slot text not null,
  hospital text not null,
  imported_by uuid references public.profiles(id) on delete set null,
  imported_at timestamptz not null default now(),
  assignment_count int not null default 0,
  inserted_count int not null default 0,
  updated_count int not null default 0,
  removed_count int not null default 0,
  skipped_manual_count int not null default 0,
  skipped_approved_count int not null default 0,
  invalid_count int not null default 0,
  unmatched_cells jsonb not null default '[]'::jsonb,
  primary key(resource_id, resource_updated_at)
);

alter table public.official_roster_import_runs enable row level security;

drop policy if exists official_roster_import_runs_admin_read
  on public.official_roster_import_runs;
create policy official_roster_import_runs_admin_read
on public.official_roster_import_runs
for select
to authenticated
using (public.is_admin());

grant select on public.official_roster_import_runs to authenticated;
revoke insert, update, delete on public.official_roster_import_runs from authenticated;

-- L'application appelle cette fonction avant de télécharger/reparser un PDF
-- déjà traité. Cela protège les corrections manuelles faites ensuite par le médecin.
create or replace function public.official_roster_import_is_current(
  p_resource_id uuid,
  p_resource_updated_at timestamptz
)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;
  return exists(
    select 1
    from public.official_roster_import_runs r
    where r.resource_id=p_resource_id
      and r.resource_updated_at=p_resource_updated_at
  );
end;
$$;

revoke all on function public.official_roster_import_is_current(uuid,timestamptz)
  from public,anon;
grant execute on function public.official_roster_import_is_current(uuid,timestamptz)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 3) Import autoritaire des affectations détectées dans le PDF
-- ---------------------------------------------------------------------------
create or replace function public.import_official_emergency_roster(
  p_resource_id uuid,
  p_resource_updated_at timestamptz,
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
  v_hospital text;
  v_item jsonb;
  v_profile public.profiles%rowtype;
  v_existing public.planning_entries%rowtype;
  v_date date;
  v_shift text;
  v_profile_id uuid;
  v_month_status text;
  v_inserted int:=0;
  v_updated int:=0;
  v_removed int:=0;
  v_skipped_manual int:=0;
  v_skipped_approved int:=0;
  v_invalid int:=0;
  v_assignment_count int:=0;
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;
  perform set_config('gardeflow.official_import','1',true);

  if jsonb_typeof(coalesce(p_assignments,'[]'::jsonb)) <> 'array' then
    raise exception 'Affectations invalides';
  end if;
  if jsonb_typeof(coalesce(p_unmatched_cells,'[]'::jsonb)) <> 'array' then
    p_unmatched_cells:='[]'::jsonb;
  end if;

  select * into v_resource
  from public.shared_resources
  where id=p_resource_id and kind='official_pdf'
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

  if exists(
    select 1 from public.official_roster_import_runs r
    where r.resource_id=p_resource_id and r.resource_updated_at=p_resource_updated_at
  ) then
    return jsonb_build_object(
      'already_processed',true,
      'inserted',0,'updated',0,'removed',0,
      'skipped_manual',0,'skipped_approved',0,'invalid',0
    );
  end if;

  -- Un PDF remplacé peut retirer certaines affectations. On retire uniquement
  -- les anciennes gardes encore marquées comme importées et dont le mois n'est
  -- pas validé. Une garde modifiée par son médecin a déjà perdu ce marquage.
  for v_existing in
    select e.*
    from public.planning_entries e
    where e.source_type='official_emergency'
      and e.source_resource_id=p_resource_id
      and e.deleted_at is null
      and not exists (
        select 1
        from jsonb_array_elements(coalesce(p_assignments,'[]'::jsonb)) a
        where (a->>'profile_id')::uuid=e.owner_id
          and (a->>'date')::date=e.date_str
      )
      -- Si une cellule de cette date n'a pas pu être rapprochée d'un compte,
      -- on conserve l'ancienne affectation plutôt que de la supprimer à tort.
      and not exists (
        select 1
        from jsonb_array_elements(coalesce(p_unmatched_cells,'[]'::jsonb)) u
        where (u->>'date')::date=e.date_str
      )
    for update
  loop
    select pm.status into v_month_status
    from public.planning_months pm
    where pm.owner_id=v_existing.owner_id
      and pm.year=extract(year from v_existing.date_str)::int
      and pm.month=extract(month from v_existing.date_str)::int;

    if v_month_status='approved' then
      v_skipped_approved:=v_skipped_approved+1;
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

    update public.planning_entries
    set deleted_at=now()
    where id=v_existing.id;
    v_removed:=v_removed+1;
  end loop;

  for v_item in
    select value from jsonb_array_elements(coalesce(p_assignments,'[]'::jsonb))
  loop
    v_assignment_count:=v_assignment_count+1;
    begin
      v_profile_id:=(v_item->>'profile_id')::uuid;
      v_date:=(v_item->>'date')::date;
      v_shift:=v_item->>'shift_id';
    exception when others then
      v_invalid:=v_invalid+1;
      continue;
    end;

    if v_shift not in ('urg-jour','urg-nuit','urg-24h') then
      v_invalid:=v_invalid+1;
      continue;
    end if;

    select * into v_profile
    from public.profiles p
    where p.id=v_profile_id
      and p.account_status='active'
      and p.hospital=v_hospital;
    if not found then
      v_invalid:=v_invalid+1;
      continue;
    end if;

    select pm.status into v_month_status
    from public.planning_months pm
    where pm.owner_id=v_profile.id
      and pm.year=extract(year from v_date)::int
      and pm.month=extract(month from v_date)::int;
    if v_month_status='approved' then
      v_skipped_approved:=v_skipped_approved+1;
      continue;
    end if;

    insert into public.planning_months(owner_id,year,month,status,updated_at)
    values(
      v_profile.id,
      extract(year from v_date)::int,
      extract(month from v_date)::int,
      'draft',now()
    )
    on conflict(owner_id,year,month) do update
      set status='draft',submitted_at=null,reviewed_at=null,reviewed_by=null,
          rejection_reason=null,updated_at=now()
      where public.planning_months.status<>'approved';

    select * into v_existing
    from public.planning_entries e
    where e.owner_id=v_profile.id
      and e.date_str=v_date
      and e.deleted_at is null
    for update;

    if found then
      if v_existing.source_type='official_emergency'
         and v_existing.source_resource_id=p_resource_id then
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
        -- Le médecin a déjà saisi/corrigé cette date : sa version reste prioritaire.
        v_skipped_manual:=v_skipped_manual+1;
      end if;
    else
      insert into public.planning_entries(
        id,date_str,shift_id,owner_id,owner_phone,owner_name,created_at,
        source_type,source_resource_id,source_resource_updated_at
      ) values (
        'pdf-'||replace(gen_random_uuid()::text,'-',''),
        v_date,v_shift,v_profile.id,v_profile.phone,
        trim(v_profile.prenom||' '||v_profile.nom),now(),
        'official_emergency',p_resource_id,p_resource_updated_at
      );
      v_inserted:=v_inserted+1;
    end if;
  end loop;

  insert into public.official_roster_import_runs(
    resource_id,resource_updated_at,slot,hospital,imported_by,
    assignment_count,inserted_count,updated_count,removed_count,
    skipped_manual_count,skipped_approved_count,invalid_count,unmatched_cells
  ) values (
    p_resource_id,p_resource_updated_at,v_resource.slot,v_hospital,auth.uid(),
    v_assignment_count,v_inserted,v_updated,v_removed,
    v_skipped_manual,v_skipped_approved,v_invalid,coalesce(p_unmatched_cells,'[]'::jsonb)
  );

  return jsonb_build_object(
    'already_processed',false,
    'inserted',v_inserted,
    'updated',v_updated,
    'removed',v_removed,
    'skipped_manual',v_skipped_manual,
    'skipped_approved',v_skipped_approved,
    'invalid',v_invalid,
    'assignments',v_assignment_count
  );
end;
$$;

revoke all on function public.import_official_emergency_roster(uuid,timestamptz,jsonb,jsonb)
  from public,anon;
grant execute on function public.import_official_emergency_roster(uuid,timestamptz,jsonb,jsonb)
  to authenticated;

-- Vérifications utiles après un premier import :
-- select * from public.official_roster_import_runs order by imported_at desc;
-- select date_str,owner_name,shift_id,source_type from public.planning_entries
-- where source_type='official_emergency' and deleted_at is null order by date_str,owner_name;
