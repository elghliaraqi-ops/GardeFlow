-- OBSOLÈTE POUR V10.2
-- Ce fichier est conservé uniquement pour l'historique de V10.1.
-- Pour l'application V10.2, exécuter patch_v10_2_self_validation_tiles_notifications.sql
-- directement après patch_v10_business_refactor.sql.
--
-- HUIM6 Planning V10.1 — retour au concept "tuiles + validation mensuelle"
-- À exécuter UNE FOIS après patch_v10_business_refactor.sql.
--
-- Principes :
-- 1) chaque médecin construit son propre calendrier avec les tuiles
--    Service/Urgences Jour, 24H, Nuit + Congé ;
-- 2) le mois est ensuite envoyé en validation ;
-- 3) l'administrateur valide/refuse le calendrier complet ;
-- 4) grade médical (junior/senior) et rôle admin restent totalement séparés.

-- ---------------------------------------------------------------------------
-- 1) Statut de validation mensuelle du calendrier
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

-- Tout planning déjà présent avant cette migration était considéré officiel.
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

alter table public.planning_months enable row level security;
drop policy if exists planning_months_select on public.planning_months;
create policy planning_months_select on public.planning_months
for select to authenticated using (
  owner_id=auth.uid() or public.is_admin()
);

revoke insert,update,delete on public.planning_months from authenticated;
grant select on public.planning_months to authenticated;

-- ---------------------------------------------------------------------------
-- 2) Les médecins peuvent composer leur propre brouillon par RPC
-- ---------------------------------------------------------------------------
create or replace function public.save_my_planning_entry(p_date date,p_shift_id text)
returns text
language plpgsql
security definer set search_path=public
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

  if month_state='submitted' then raise exception 'Calendrier déjà envoyé à l’administrateur'; end if;
  if month_state='approved' then raise exception 'Calendrier déjà validé'; end if;

  insert into public.planning_months(owner_id,year,month,status,updated_at)
  values(me.id,y,m,'draft',now())
  on conflict(owner_id,year,month) do update
    set status='draft',rejection_reason=null,reviewed_at=null,reviewed_by=null,updated_at=now()
    where public.planning_months.status in ('draft','rejected');

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
      set shift_id=p_shift_id,owner_phone=me.phone,owner_name=trim(me.prenom||' '||me.nom),leave_request_id=null
      where id=existing.id;
    entry_id:=existing.id;
  else
    entry_id:='p-'||replace(gen_random_uuid()::text,'-','');
    insert into public.planning_entries(id,date_str,shift_id,owner_id,owner_phone,owner_name,created_at)
    values(entry_id,p_date,p_shift_id,me.id,me.phone,trim(me.prenom||' '||me.nom),now());
  end if;

  return entry_id;
end;
$$;

create or replace function public.delete_my_planning_entry(p_entry_id text)
returns void
language plpgsql
security definer set search_path=public
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

  select * into e from public.planning_entries
  where id=p_entry_id and owner_id=me.id and deleted_at is null
  for update;
  if not found then raise exception 'Affectation introuvable'; end if;
  if e.date_str < current_date then raise exception 'Une date passée ne peut plus être modifiée'; end if;

  y:=extract(year from e.date_str)::int;
  m:=extract(month from e.date_str)::int;
  select status into month_state from public.planning_months
  where owner_id=me.id and year=y and month=m for update;
  if month_state='submitted' then raise exception 'Calendrier déjà envoyé à l’administrateur'; end if;
  if month_state='approved' then raise exception 'Calendrier déjà validé'; end if;

  if exists(
    select 1 from public.exchange_requests r
    where r.status in ('pendingB','pendingAdmin')
      and (r.planning_entry_id=e.id or r.target_planning_entry_id=e.id)
  ) then raise exception 'Cette garde est verrouillée par une demande active'; end if;

  update public.planning_entries set deleted_at=now() where id=e.id;
  insert into public.planning_months(owner_id,year,month,status,updated_at)
  values(me.id,y,m,'draft',now())
  on conflict(owner_id,year,month) do update
    set status='draft',rejection_reason=null,reviewed_at=null,reviewed_by=null,updated_at=now()
    where public.planning_months.status in ('draft','rejected');
end;
$$;

-- Un mois vide peut aussi être envoyé : "aucune garde" est un calendrier valide.
create or replace function public.submit_my_planning_month(p_year int,p_month int)
returns void
language plpgsql
security definer set search_path=public
as $$
declare
  me public.profiles%rowtype;
  first_day date;
  current_state text;
begin
  select * into me from public.profiles where id=auth.uid() and account_status='active';
  if not found then raise exception 'Compte actif requis'; end if;
  if p_year not between 2020 and 2100 or p_month not between 1 and 12 then raise exception 'Mois invalide'; end if;
  first_day:=make_date(p_year,p_month,1);
  if first_day < date_trunc('month',current_date)::date then raise exception 'Un mois passé ne peut plus être envoyé'; end if;

  select status into current_state from public.planning_months
  where owner_id=me.id and year=p_year and month=p_month for update;
  if current_state='submitted' then raise exception 'Calendrier déjà en attente'; end if;
  if current_state='approved' then raise exception 'Calendrier déjà validé'; end if;

  insert into public.planning_months(owner_id,year,month,status,submitted_at,reviewed_at,reviewed_by,rejection_reason,updated_at)
  values(me.id,p_year,p_month,'submitted',now(),null,null,null,now())
  on conflict(owner_id,year,month) do update
    set status='submitted',submitted_at=now(),reviewed_at=null,reviewed_by=null,rejection_reason=null,updated_at=now();

  perform public.write_audit(
    'planning_month.submitted','planning_month',me.id::text||':'||p_year||':'||p_month,
    me.id,trim(me.prenom||' '||me.nom),null,
    jsonb_build_object('year',p_year,'month',p_month)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 3) Validation du calendrier complet par l'admin
-- ---------------------------------------------------------------------------
create or replace function public.review_planning_month(
  p_owner_id uuid,
  p_year int,
  p_month int,
  p_action text,
  p_reason text default null
)
returns void
language plpgsql
security definer set search_path=public
as $$
declare
  rec public.planning_months%rowtype;
  owner public.profiles%rowtype;
begin
  if not public.is_admin() then raise exception 'Réservé à l’administrateur'; end if;
  if p_owner_id=auth.uid() then raise exception 'Votre calendrier personnel doit être validé par un autre administrateur'; end if;

  select * into owner from public.profiles where id=p_owner_id and account_status='active';
  if not found then raise exception 'Médecin introuvable ou inactif'; end if;

  select * into rec from public.planning_months
  where owner_id=p_owner_id and year=p_year and month=p_month
  for update;
  if not found or rec.status<>'submitted' then raise exception 'Calendrier non disponible pour validation'; end if;

  if p_action='approve' then
    update public.planning_months
      set status='approved',reviewed_at=now(),reviewed_by=auth.uid(),rejection_reason=null,updated_at=now()
      where owner_id=p_owner_id and year=p_year and month=p_month;
    perform public.write_audit(
      'planning_month.approved','planning_month',p_owner_id::text||':'||p_year||':'||p_month,
      p_owner_id,trim(owner.prenom||' '||owner.nom),null,
      jsonb_build_object('year',p_year,'month',p_month)
    );
  elsif p_action='reject' then
    if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Motif de refus obligatoire'; end if;
    update public.planning_months
      set status='rejected',reviewed_at=now(),reviewed_by=auth.uid(),rejection_reason=trim(p_reason),updated_at=now()
      where owner_id=p_owner_id and year=p_year and month=p_month;
    perform public.write_audit(
      'planning_month.rejected','planning_month',p_owner_id::text||':'||p_year||':'||p_month,
      p_owner_id,trim(owner.prenom||' '||owner.nom),trim(p_reason),
      jsonb_build_object('year',p_year,'month',p_month)
    );
  else
    raise exception 'Action invalide';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4) L'admin garde tous ses droits, indépendamment du grade junior/senior
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_planning(p_owner_id uuid,p_date date,p_shift_id text)
returns text
language plpgsql security definer set search_path=public
as $$
declare
  owner public.profiles%rowtype;
  existing public.planning_entries%rowtype;
  entry_id text;
  y int:=extract(year from p_date)::int;
  m int:=extract(month from p_date)::int;
begin
  if not public.is_admin() then raise exception 'Réservé à l’administrateur'; end if;
  if p_date < current_date then raise exception 'Une date passée ne peut pas être créée ou modifiée'; end if;
  if p_shift_id not in ('service-jour','service-24h','service-nuit','urg-jour','urg-24h','urg-nuit','conge') then
    raise exception 'Type de tuile invalide';
  end if;

  select * into owner from public.profiles where id=p_owner_id and account_status='active';
  if not found then raise exception 'Médecin introuvable ou inactif'; end if;

  select * into existing from public.planning_entries
  where owner_id=p_owner_id and date_str=p_date and deleted_at is null
  for update;

  if found then
    -- Une correction admin est prioritaire. Toute demande d'échange/transfert
    -- encore active sur cette garde est annulée avant la modification afin
    -- de ne jamais laisser une demande pointer vers une ancienne tuile.
    update public.exchange_requests
       set status='cancelled'
     where status in ('pendingB','pendingAdmin')
       and (planning_entry_id=existing.id or target_planning_entry_id=existing.id);

    perform set_config('huim6.review_request','1',true);
    update public.planning_entries set shift_id=p_shift_id,leave_request_id=null where id=existing.id;
    entry_id:=existing.id;
  else
    entry_id:='p-'||replace(gen_random_uuid()::text,'-','');
    insert into public.planning_entries(id,date_str,shift_id,owner_id,owner_phone,owner_name,created_at)
    values(entry_id,p_date,p_shift_id,owner.id,owner.phone,trim(owner.prenom||' '||owner.nom),now());
  end if;

  insert into public.planning_months(owner_id,year,month,status,updated_at)
  values(owner.id,y,m,'draft',now())
  on conflict(owner_id,year,month) do nothing;

  perform public.write_audit(
    'planning.assigned','planning_entry',entry_id,owner.id,trim(owner.prenom||' '||owner.nom),null,
    jsonb_build_object('date',p_date,'shift_id',p_shift_id,'actor_role','admin')
  );
  return entry_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5) Transfert / échange uniquement sur des calendriers déjà validés
-- ---------------------------------------------------------------------------
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

-- Un médecin voit toujours son propre brouillon. Un administrateur voit tout.
-- Les autres médecins du même établissement ne voient le planning d'un collègue
-- qu'une fois le mois validé par l'administration.
drop policy if exists planning_select on public.planning_entries;
create policy planning_select on public.planning_entries
for select to authenticated using (
  public.is_admin()
  or owner_id=auth.uid()
  or (
    public.current_account_active()
    and public.planning_month_is_approved(owner_id,date_str)
    and exists(
      select 1 from public.profiles p
      where p.id=planning_entries.owner_id
        and p.account_status='active'
        and p.hospital=public.current_hospital()
    )
  )
);

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
  if not public.planning_month_is_approved(from_profile.id,source.date_str) then raise exception 'Le calendrier source n’est pas validé'; end if;
  if not public.planning_month_is_approved(to_profile.id,source.date_str) then raise exception 'Le calendrier du destinataire n’est pas validé pour ce mois'; end if;
  if public.guard_has_started(source.date_str,source.shift_id) then raise exception 'La garde source est déjà commencée ou passée'; end if;
  new.date_str:=source.date_str;
  new.shift_id:=source.shift_id;

  if new.type='exchange' then
    if new.target_planning_entry_id is null then raise exception 'Garde cible obligatoire'; end if;
    select * into target from public.planning_entries
    where id=new.target_planning_entry_id and owner_id=to_profile.id and deleted_at is null;
    if not found or target.shift_id='conge' then raise exception 'Garde cible invalide'; end if;
    if not public.planning_month_is_approved(to_profile.id,target.date_str) then raise exception 'Le calendrier cible n’est pas validé'; end if;
    if not public.planning_month_is_approved(from_profile.id,target.date_str) then raise exception 'Le mois de destination du demandeur n’est pas validé'; end if;
    if public.guard_has_started(target.date_str,target.shift_id) then raise exception 'La garde cible est déjà commencée ou passée'; end if;
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
create trigger fill_exchange_identity_trigger before insert on public.exchange_requests
for each row execute procedure public.fill_exchange_identity();

-- ---------------------------------------------------------------------------
-- 6) Realtime + permissions RPC
-- ---------------------------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.planning_months;
exception when duplicate_object then null; end $$;

revoke all on function public.save_my_planning_entry(date,text) from public,anon;
revoke all on function public.delete_my_planning_entry(text) from public,anon;
revoke all on function public.submit_my_planning_month(integer,integer) from public,anon;
revoke all on function public.review_planning_month(uuid,integer,integer,text,text) from public,anon;
revoke all on function public.planning_month_is_approved(uuid,date) from public,anon;

grant execute on function public.save_my_planning_entry(date,text) to authenticated;
grant execute on function public.delete_my_planning_entry(text) to authenticated;
grant execute on function public.submit_my_planning_month(integer,integer) to authenticated;
grant execute on function public.review_planning_month(uuid,integer,integer,text,text) to authenticated;
grant execute on function public.planning_month_is_approved(uuid,date) to authenticated;

-- IMPORTANT : junior/senior n'accorde aucun droit administratif.
-- Les droits restent exclusivement pilotés par profiles.role='admin'.
