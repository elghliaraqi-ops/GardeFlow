-- HUIM6 Planning V10.2 — tuiles + validation définitive par le médecin
--
-- À exécuter UNE FOIS après patch_v10_business_refactor.sql.
-- Ce patch est cumulatif : il fonctionne même si patch_v10_1_tiles_calendar_validation.sql
-- a déjà été exécuté. Dans ce cas, il remplace l'ancien workflow de validation admin.
--
-- Règles métier V10.2 :
-- 1) chaque médecin compose SON calendrier avec les tuiles
--    Service/Urgences Jour, 24H, Nuit + Congé ;
-- 2) le médecin valide lui-même le mois, définitivement et sans retour en arrière ;
-- 3) l'admin ne valide PAS le calendrier complet ;
-- 4) l'admin valide les transferts, échanges et congés ;
-- 5) seul l'admin peut supprimer une garde/congé d'un calendrier validé ;
-- 6) junior/senior est purement informatif : seul profiles.role='admin' donne les droits admin.

-- ---------------------------------------------------------------------------
-- 1) État mensuel du calendrier
-- ---------------------------------------------------------------------------
create table if not exists public.planning_months (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  year int not null check (year between 2020 and 2100),
  month int not null check (month between 1 and 12),
  status text not null default 'draft' check (status in ('draft','submitted','approved','rejected')),
  submitted_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id),
  rejection_reason text,
  updated_at timestamptz not null default now(),
  primary key(owner_id,year,month)
);

create index if not exists planning_months_status_idx
  on public.planning_months(status,year,month);

-- Toutes les affectations qui existaient avant l'introduction du verrouillage
-- mensuel étaient déjà des affectations officielles : leurs mois restent validés.
insert into public.planning_months(owner_id,year,month,status,submitted_at,reviewed_at,updated_at)
select distinct
  p.owner_id,
  extract(year from p.date_str)::int,
  extract(month from p.date_str)::int,
  'approved',
  p.created_at,
  p.created_at,
  now()
from public.planning_entries p
where p.deleted_at is null and p.owner_id is not null
on conflict(owner_id,year,month) do nothing;

-- Si V10.1 a été utilisée quelques instants, les calendriers qui attendaient
-- l'admin redeviennent modifiables. Les mois déjà approuvés restent verrouillés.
update public.planning_months
set status='draft',
    submitted_at=null,
    reviewed_at=null,
    reviewed_by=null,
    rejection_reason=null,
    updated_at=now()
where status in ('submitted','rejected');

alter table public.planning_months enable row level security;
drop policy if exists planning_months_select on public.planning_months;
create policy planning_months_select on public.planning_months
for select to authenticated using (
  owner_id=auth.uid() or public.is_admin()
);
revoke insert,update,delete on public.planning_months from authenticated;
grant select on public.planning_months to authenticated;

create or replace function public.planning_month_is_approved(p_owner_id uuid,p_date date)
returns boolean language sql stable security definer set search_path=public
as $$
  select exists(
    select 1 from public.planning_months pm
    where pm.owner_id=p_owner_id
      and pm.year=extract(year from p_date)::int
      and pm.month=extract(month from p_date)::int
      and pm.status='approved'
  )
$$;
revoke all on function public.planning_month_is_approved(uuid,date) from public,anon;
grant execute on function public.planning_month_is_approved(uuid,date) to authenticated;

-- ---------------------------------------------------------------------------
-- 2) Composition du calendrier par le médecin : tuiles personnelles
-- ---------------------------------------------------------------------------
create or replace function public.save_my_planning_entry(p_date date,p_shift_id text)
returns text
language plpgsql security definer set search_path=public
as $$
declare
  me public.profiles%rowtype;
  month_state text;
  existing public.planning_entries%rowtype;
  entry_id text;
  y int:=extract(year from p_date)::int;
  m int:=extract(month from p_date)::int;
begin
  select * into me from public.profiles where id=auth.uid() and account_status='active';
  if not found then raise exception 'Compte actif requis'; end if;
  if p_date < current_date then raise exception 'Une date passée ne peut plus être modifiée'; end if;
  if p_shift_id not in ('service-jour','service-24h','service-nuit','urg-jour','urg-24h','urg-nuit','conge') then
    raise exception 'Type de tuile invalide';
  end if;

  select status into month_state
  from public.planning_months
  where owner_id=me.id and year=y and month=m
  for update;

  if month_state='approved' then
    raise exception 'Calendrier validé définitivement : aucune modification directe n’est possible';
  end if;

  insert into public.planning_months(owner_id,year,month,status,updated_at)
  values(me.id,y,m,'draft',now())
  on conflict(owner_id,year,month) do update
    set status='draft',submitted_at=null,reviewed_at=null,reviewed_by=null,rejection_reason=null,updated_at=now()
    where public.planning_months.status<>'approved';

  select * into existing
  from public.planning_entries
  where owner_id=me.id and date_str=p_date and deleted_at is null
  for update;

  if found then
    if exists(
      select 1 from public.exchange_requests r
      where r.status in ('pendingB','pendingAdmin')
        and (r.planning_entry_id=existing.id or r.target_planning_entry_id=existing.id)
    ) then raise exception 'Cette garde est verrouillée par une demande active'; end if;

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
      entry_id,p_date,p_shift_id,me.id,me.phone,trim(me.prenom||' '||me.nom),now()
    );
  end if;

  return entry_id;
end;
$$;

create or replace function public.delete_my_planning_entry(p_entry_id text)
returns void
language plpgsql security definer set search_path=public
as $$
declare
  me public.profiles%rowtype;
  e public.planning_entries%rowtype;
  month_state text;
  y int;
  m int;
begin
  select * into me from public.profiles where id=auth.uid() and account_status='active';
  if not found then raise exception 'Compte actif requis'; end if;

  select * into e
  from public.planning_entries
  where id=p_entry_id and owner_id=me.id and deleted_at is null
  for update;
  if not found then raise exception 'Affectation introuvable'; end if;
  if e.date_str < current_date then raise exception 'Une date passée ne peut plus être modifiée'; end if;

  y:=extract(year from e.date_str)::int;
  m:=extract(month from e.date_str)::int;
  select status into month_state
  from public.planning_months
  where owner_id=me.id and year=y and month=m
  for update;

  if month_state='approved' then
    raise exception 'Calendrier validé définitivement : seul un administrateur peut supprimer une garde validée';
  end if;

  if exists(
    select 1 from public.exchange_requests r
    where r.status in ('pendingB','pendingAdmin')
      and (r.planning_entry_id=e.id or r.target_planning_entry_id=e.id)
  ) then raise exception 'Cette garde est verrouillée par une demande active'; end if;

  update public.planning_entries set deleted_at=now() where id=e.id;
  insert into public.planning_months(owner_id,year,month,status,updated_at)
  values(me.id,y,m,'draft',now())
  on conflict(owner_id,year,month) do update
    set status='draft',submitted_at=null,reviewed_at=null,reviewed_by=null,rejection_reason=null,updated_at=now()
    where public.planning_months.status<>'approved';
end;
$$;

revoke all on function public.save_my_planning_entry(date,text) from public,anon;
revoke all on function public.delete_my_planning_entry(text) from public,anon;
grant execute on function public.save_my_planning_entry(date,text) to authenticated;
grant execute on function public.delete_my_planning_entry(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3) Validation définitive PAR LE MÉDECIN
--    Les tuiles Congé deviennent des demandes à traiter par l'admin.
-- ---------------------------------------------------------------------------
drop function if exists public.submit_my_planning_month(integer,integer);
create function public.submit_my_planning_month(p_year int,p_month int)
returns text[]
language plpgsql security definer set search_path=public
as $$
declare
  me public.profiles%rowtype;
  first_day date;
  last_day date;
  current_state text;
  range_rec record;
  request_id text;
  first_entry text;
  created_leave_ids text[] := array[]::text[];
begin
  select * into me from public.profiles where id=auth.uid() and account_status='active';
  if not found then raise exception 'Compte actif requis'; end if;
  if p_year not between 2020 and 2100 or p_month not between 1 and 12 then
    raise exception 'Mois invalide';
  end if;

  first_day:=make_date(p_year,p_month,1);
  last_day:=(first_day + interval '1 month - 1 day')::date;
  if first_day < date_trunc('month',current_date)::date then
    raise exception 'Un mois passé ne peut plus être validé';
  end if;

  select status into current_state
  from public.planning_months
  where owner_id=me.id and year=p_year and month=p_month
  for update;
  if current_state='approved' then
    raise exception 'Calendrier déjà validé définitivement';
  end if;

  -- Réutilise une demande de congé active existante si elle couvre déjà la tuile.
  update public.planning_entries p
  set leave_request_id = (
    select l.id
    from public.leave_requests l
    where l.owner_id=me.id
      and l.status in ('pendingAdmin','approved')
      and p.date_str between l.start_date and l.end_date
    order by l.created_at desc
    limit 1
  )
  where p.owner_id=me.id
    and p.deleted_at is null
    and p.shift_id='conge'
    and p.date_str between first_day and last_day
    and p.leave_request_id is null
    and exists (
      select 1 from public.leave_requests l
      where l.owner_id=me.id
        and l.status in ('pendingAdmin','approved')
        and p.date_str between l.start_date and l.end_date
    );

  -- Regroupe les tuiles Congé contiguës en demandes de période.
  for range_rec in
    with conge_days as (
      select
        p.date_str,
        p.date_str - (row_number() over(order by p.date_str))::int as grp
      from public.planning_entries p
      where p.owner_id=me.id
        and p.deleted_at is null
        and p.shift_id='conge'
        and p.leave_request_id is null
        and p.date_str between first_day and last_day
    )
    select min(date_str)::date as start_date, max(date_str)::date as end_date
    from conge_days
    group by grp
    order by min(date_str)
  loop
    request_id:='lr-'||replace(gen_random_uuid()::text,'-','');

    insert into public.leave_requests(
      id,date_str,start_date,end_date,owner_id,owner_phone,owner_name,status,created_at
    ) values (
      request_id,
      range_rec.start_date::text,
      range_rec.start_date,
      range_rec.end_date,
      me.id,
      me.phone,
      trim(me.prenom||' '||me.nom),
      'pendingAdmin',
      now()
    );

    update public.planning_entries
       set leave_request_id=request_id
     where owner_id=me.id
       and deleted_at is null
       and shift_id='conge'
       and leave_request_id is null
       and date_str between range_rec.start_date and range_rec.end_date;

    select id into first_entry
    from public.planning_entries
    where owner_id=me.id and deleted_at is null and leave_request_id=request_id
    order by date_str
    limit 1;

    update public.leave_requests
       set planning_entry_id=first_entry
     where id=request_id;

    created_leave_ids:=array_append(created_leave_ids,request_id);

    perform public.write_audit(
      'leave.created','leave_request',request_id,
      me.id,trim(me.prenom||' '||me.nom),null,
      jsonb_build_object('start_date',range_rec.start_date,'end_date',range_rec.end_date,'source','planning_tile')
    );
  end loop;

  -- Même un mois vide peut être validé : après cette action il est figé.
  insert into public.planning_months(
    owner_id,year,month,status,submitted_at,reviewed_at,reviewed_by,rejection_reason,updated_at
  ) values (
    me.id,p_year,p_month,'approved',now(),null,null,null,now()
  )
  on conflict(owner_id,year,month) do update
    set status='approved',submitted_at=now(),reviewed_at=null,reviewed_by=null,rejection_reason=null,updated_at=now();

  perform public.write_audit(
    'planning_month.finalized','planning_month',me.id::text||':'||p_year||':'||p_month,
    me.id,trim(me.prenom||' '||me.nom),null,
    jsonb_build_object('year',p_year,'month',p_month,'irreversible',true)
  );

  return created_leave_ids;
end;
$$;
revoke all on function public.submit_my_planning_month(integer,integer) from public,anon;
grant execute on function public.submit_my_planning_month(integer,integer) to authenticated;

-- Les anciens RPC de validation de calendrier / affectation admin ne font plus
-- partie du concept final. Leur suppression empêche aussi un vieux client de les utiliser.
drop function if exists public.review_planning_month(uuid,integer,integer,text,text);
drop function if exists public.admin_set_planning(uuid,date,text);

-- ---------------------------------------------------------------------------
-- 4) Congés : l'admin approuve/refuse seulement la demande de congé.
--    Approbation = la tuile reste ; refus = la tuile est retirée sans rouvrir le mois.
-- ---------------------------------------------------------------------------
create or replace function public.review_leave_request(p_request_id text,p_action text)
returns void
language plpgsql security definer set search_path=public
as $$
declare
  r public.leave_requests%rowtype;
  conflict_dates text;
  first_entry text;
begin
  if not public.is_admin() then raise exception 'Réservé à l’administrateur'; end if;

  select * into r from public.leave_requests where id=p_request_id for update;
  if not found then raise exception 'Demande de congé introuvable'; end if;
  if r.status<>'pendingAdmin' then raise exception 'Demande déjà traitée'; end if;
  if r.owner_id=auth.uid() then raise exception 'Un administrateur ne peut pas valider son propre congé'; end if;

  perform set_config('huim6.review_request','1',true);

  if p_action='reject' then
    update public.planning_entries
       set deleted_at=now()
     where leave_request_id=r.id and shift_id='conge' and deleted_at is null;

    update public.leave_requests
       set status='rejectedAdmin',reviewed_at=now()
     where id=p_request_id;

    perform public.write_audit(
      'leave.rejected','leave_request',p_request_id,r.owner_id,r.owner_name,null,
      jsonb_build_object('start_date',r.start_date,'end_date',r.end_date)
    );
    return;
  elsif p_action<>'approve' then
    raise exception 'Action invalide';
  end if;

  -- Une demande créée hors tuile ne remplace jamais silencieusement une garde.
  select string_agg(to_char(p.date_str,'DD/MM/YYYY'),', ' order by p.date_str)
  into conflict_dates
  from public.planning_entries p
  where p.owner_id=r.owner_id
    and p.deleted_at is null
    and p.shift_id<>'conge'
    and p.date_str between r.start_date and r.end_date;
  if conflict_dates is not null then
    raise exception 'Gardes à couvrir avant approbation : %', conflict_dates;
  end if;

  -- Si la demande vient des tuiles du calendrier, elles existent déjà.
  select id into first_entry
  from public.planning_entries
  where leave_request_id=r.id and shift_id='conge' and deleted_at is null
  order by date_str
  limit 1;

  if first_entry is null then
    -- Compatibilité avec une ancienne demande de congé créée séparément.
    insert into public.planning_entries(
      id,date_str,shift_id,owner_id,owner_phone,owner_name,leave_request_id,created_at
    )
    select
      'leave-'||replace(gen_random_uuid()::text,'-',''),
      d::date,
      'conge',
      r.owner_id,
      r.owner_phone,
      r.owner_name,
      r.id,
      now()
    from generate_series(r.start_date::timestamp,r.end_date::timestamp,interval '1 day') d
    where not exists (
      select 1 from public.planning_entries p
      where p.owner_id=r.owner_id and p.date_str=d::date and p.deleted_at is null
    )
    order by d;

    select id into first_entry
    from public.planning_entries
    where leave_request_id=r.id and deleted_at is null
    order by date_str
    limit 1;
  end if;

  update public.leave_requests
     set status='approved',planning_entry_id=first_entry,reviewed_at=now()
   where id=p_request_id;

  perform public.write_audit(
    'leave.approved','leave_request',p_request_id,r.owner_id,r.owner_name,null,
    jsonb_build_object('start_date',r.start_date,'end_date',r.end_date)
  );
end;
$$;
revoke all on function public.review_leave_request(text,text) from public,anon;
grant execute on function public.review_leave_request(text,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5) Seul l'admin peut supprimer une affectation d'un mois validé.
-- ---------------------------------------------------------------------------
create or replace function public.admin_delete_planning(p_entry_id text,p_reason text)
returns void
language plpgsql security definer set search_path=public
as $$
declare e public.planning_entries%rowtype;
begin
  if not public.is_admin() then raise exception 'Réservé à l’administrateur'; end if;
  if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Motif de suppression obligatoire'; end if;

  select * into e
  from public.planning_entries
  where id=p_entry_id and deleted_at is null
  for update;
  if not found then raise exception 'Affectation introuvable'; end if;

  if not public.planning_month_is_approved(e.owner_id,e.date_str) then
    raise exception 'Seules les affectations d’un calendrier validé peuvent être supprimées';
  end if;

  if e.shift_id='conge' and e.leave_request_id is not null and not exists(
    select 1 from public.leave_requests l
    where l.id=e.leave_request_id and l.status='approved'
  ) then
    raise exception 'Ce congé est encore en attente : utilisez Approuver ou Refuser';
  end if;

  perform set_config('huim6.review_request','1',true);

  update public.exchange_requests
     set status='cancelled'
   where status in ('pendingB','pendingAdmin')
     and (planning_entry_id=p_entry_id or target_planning_entry_id=p_entry_id);

  if e.shift_id='conge' and e.leave_request_id is not null then
    update public.planning_entries
       set deleted_at=now()
     where leave_request_id=e.leave_request_id and deleted_at is null;

    update public.leave_requests
       set status='cancelled',reviewed_at=now()
     where id=e.leave_request_id and status='approved';
  else
    update public.planning_entries set deleted_at=now() where id=p_entry_id;
  end if;

  perform public.write_audit(
    'planning.deleted','planning_entry',p_entry_id,e.owner_id,e.owner_name,trim(p_reason),
    jsonb_build_object('date',e.date_str,'shift_id',e.shift_id,'leave_request_id',e.leave_request_id)
  );
end;
$$;
revoke all on function public.admin_delete_planning(text,text) from public,anon;
grant execute on function public.admin_delete_planning(text,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6) Visibilité du planning validé.
--    Le propriétaire et l'admin voient le brouillon / congé en attente.
--    Les collègues ne voient que les mois validés et les congés approuvés.
-- ---------------------------------------------------------------------------
create or replace function public.leave_request_is_approved(p_request_id text)
returns boolean
language sql stable security definer set search_path=public
as $$
  select p_request_id is null or exists(
    select 1 from public.leave_requests l
    where l.id=p_request_id and l.status='approved'
  )
$$;
revoke all on function public.leave_request_is_approved(text) from public,anon;
grant execute on function public.leave_request_is_approved(text) to authenticated;

drop policy if exists planning_select on public.planning_entries;
create policy planning_select on public.planning_entries
for select to authenticated using (
  public.is_admin()
  or owner_id=auth.uid()
  or (
    public.current_account_active()
    and public.planning_month_is_approved(owner_id,date_str)
    and (
      shift_id<>'conge'
      or public.leave_request_is_approved(leave_request_id)
    )
    and exists(
      select 1 from public.profiles p
      where p.id=planning_entries.owner_id
        and p.account_status='active'
        and p.hospital=public.current_hospital()
    )
  )
);

-- ---------------------------------------------------------------------------
-- 7) Transfert / échange : uniquement à partir de calendriers validés.
-- ---------------------------------------------------------------------------
create or replace function public.fill_exchange_identity()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  from_profile public.profiles%rowtype;
  to_profile public.profiles%rowtype;
  source public.planning_entries%rowtype;
  target public.planning_entries%rowtype;
begin
  select * into from_profile from public.profiles where id=auth.uid() and account_status='active';
  if not found then raise exception 'Compte actif requis'; end if;

  new.from_id:=from_profile.id;
  new.from_phone:=from_profile.phone;
  new.from_name:=trim(from_profile.prenom||' '||from_profile.nom);

  if new.to_id is null and new.to_phone is not null then
    select * into to_profile from public.profiles where phone=new.to_phone and account_status='active';
  else
    select * into to_profile from public.profiles where id=new.to_id and account_status='active';
  end if;
  if not found then raise exception 'Destinataire introuvable ou inactif'; end if;
  new.to_id:=to_profile.id;
  new.to_phone:=to_profile.phone;
  new.to_name:=trim(to_profile.prenom||' '||to_profile.nom);

  if new.from_id=new.to_id then raise exception 'Le demandeur et le destinataire doivent être différents'; end if;
  if from_profile.hospital is distinct from to_profile.hospital then raise exception 'Échange inter-établissements interdit'; end if;

  select * into source from public.planning_entries
  where id=new.planning_entry_id and owner_id=from_profile.id and deleted_at is null;
  if not found or source.shift_id='conge' then raise exception 'Garde source invalide'; end if;
  if not public.planning_month_is_approved(from_profile.id,source.date_str) then
    raise exception 'Le calendrier source n’est pas validé';
  end if;
  if not public.planning_month_is_approved(to_profile.id,source.date_str) then
    raise exception 'Le calendrier du destinataire n’est pas validé pour ce mois';
  end if;
  if public.guard_has_started(source.date_str,source.shift_id) then
    raise exception 'La garde source est déjà commencée ou passée';
  end if;
  new.date_str:=source.date_str;
  new.shift_id:=source.shift_id;

  if new.type='exchange' then
    if new.target_planning_entry_id is null then raise exception 'Garde cible obligatoire'; end if;
    select * into target from public.planning_entries
    where id=new.target_planning_entry_id and owner_id=to_profile.id and deleted_at is null;
    if not found or target.shift_id='conge' then raise exception 'Garde cible invalide'; end if;
    if not public.planning_month_is_approved(to_profile.id,target.date_str) then
      raise exception 'Le calendrier cible n’est pas validé';
    end if;
    if not public.planning_month_is_approved(from_profile.id,target.date_str) then
      raise exception 'Le mois de destination du demandeur n’est pas validé';
    end if;
    if public.guard_has_started(target.date_str,target.shift_id) then
      raise exception 'La garde cible est déjà commencée ou passée';
    end if;
    new.target_date_str:=target.date_str;
    new.target_shift_id:=target.shift_id;
  elsif new.type='transfer' then
    new.target_planning_entry_id:=null;
    new.target_date_str:=null;
    new.target_shift_id:=null;
  else
    raise exception 'Type de demande invalide';
  end if;

  new.status:='pendingB';
  new.created_at:=now();
  return new;
end;
$$;

drop trigger if exists fill_exchange_identity_trigger on public.exchange_requests;
create trigger fill_exchange_identity_trigger
before insert on public.exchange_requests
for each row execute procedure public.fill_exchange_identity();

-- ---------------------------------------------------------------------------
-- 8) Realtime / permissions
-- ---------------------------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.planning_months;
exception when duplicate_object then null; end $$;

-- Rappel : les mutations de planning passent par les RPC ci-dessus.
drop policy if exists planning_insert on public.planning_entries;
drop policy if exists planning_update on public.planning_entries;
drop policy if exists planning_delete on public.planning_entries;
revoke insert,update,delete on public.planning_entries from authenticated;

-- IMPORTANT : Junior/Senior n'accorde AUCUN droit administratif.
-- public.is_admin() dépend de profiles.role='admin' (et du compte actif), pas du grade.
-- Un médecin Junior + Admin dispose donc des mêmes droits admin qu'un Senior + Admin.
