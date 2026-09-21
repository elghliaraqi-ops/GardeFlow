-- HUIM6 Planning V10.0 — refonte métier et sécurité
-- À exécuter UNE FOIS après la V9.8.2.
-- Ce patch conserve les données existantes et introduit :
-- - séparation grade médical / rôle admin
-- - validation des nouveaux comptes
-- - UUID comme identité métier autoritaire
-- - dates PostgreSQL réelles
-- - gardes officielles gérées par l'administration
-- - congés sur période, y compris lorsqu'une garde doit d'abord être couverte
-- - interdiction d'auto-validation par un admin participant
-- - audit immuable des actions sensibles

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- 1) Profils : grade médical distinct du rôle + validation des nouveaux comptes
-- ---------------------------------------------------------------------------
alter table public.profiles add column if not exists medical_grade text;
alter table public.profiles add column if not exists account_status text;

update public.profiles
set medical_grade = case when fonction='senior' then 'senior' else 'junior' end
where medical_grade is null;

update public.profiles set account_status='active' where account_status is null;
-- Un ancien 'fonction=admin' ne dit rien sur le grade médical. Par défaut,
-- on le migre en junior ; le grade peut ensuite être corrigé indépendamment du rôle.
update public.profiles set fonction='junior' where fonction='admin';

alter table public.profiles drop constraint if exists profiles_fonction_check;
alter table public.profiles add constraint profiles_fonction_check check (fonction in ('junior','senior'));
alter table public.profiles drop constraint if exists profiles_medical_grade_check;
alter table public.profiles add constraint profiles_medical_grade_check check (medical_grade in ('junior','senior'));
alter table public.profiles drop constraint if exists profiles_account_status_check;
alter table public.profiles add constraint profiles_account_status_check check (account_status in ('pending','active','suspended'));

alter table public.profiles alter column medical_grade set default 'junior';
alter table public.profiles alter column medical_grade set not null;
alter table public.profiles alter column account_status set default 'pending';
alter table public.profiles alter column account_status set not null;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public
as $$
  select coalesce((
    select role='admin' and account_status='active'
    from public.profiles where id=auth.uid()
  ),false)
$$;

create or replace function public.current_profile_id()
returns uuid language sql stable security definer set search_path=public
as $$ select auth.uid() $$;

create or replace function public.current_account_active()
returns boolean language sql stable security definer set search_path=public
as $$
  select coalesce((select account_status='active' from public.profiles where id=auth.uid()),false)
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare g text;
begin
  g := coalesce(new.raw_user_meta_data->>'medical_grade', new.raw_user_meta_data->>'fonction', 'junior');
  if g not in ('junior','senior') then g := 'junior'; end if;

  insert into public.profiles(
    id,phone,nom,prenom,service,fonction,medical_grade,hospital,role,account_status
  ) values (
    new.id,
    coalesce(new.phone,new.raw_user_meta_data->>'phone'),
    coalesce(new.raw_user_meta_data->>'nom',''),
    coalesce(new.raw_user_meta_data->>'prenom',''),
    coalesce(new.raw_user_meta_data->>'service',''),
    g,
    g,
    coalesce(new.raw_user_meta_data->>'hospital',''),
    'medecin',
    'pending'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2) UUID autoritaires dans les tables métier
-- ---------------------------------------------------------------------------
alter table public.planning_entries add column if not exists owner_id uuid;
update public.planning_entries p
set owner_id = pr.id
from public.profiles pr
where p.owner_id is null and pr.phone=p.owner_phone;

alter table public.exchange_requests add column if not exists from_id uuid;
alter table public.exchange_requests add column if not exists to_id uuid;
update public.exchange_requests e set from_id=p.id from public.profiles p where e.from_id is null and p.phone=e.from_phone;
update public.exchange_requests e set to_id=p.id from public.profiles p where e.to_id is null and p.phone=e.to_phone;

alter table public.leave_requests add column if not exists owner_id uuid;
update public.leave_requests l set owner_id=p.id from public.profiles p where l.owner_id is null and p.phone=l.owner_phone;

alter table public.push_tokens add column if not exists owner_id uuid;
update public.push_tokens t set owner_id=p.id from public.profiles p where t.owner_id is null and p.phone=t.owner_phone;

-- Les FK sont ajoutées de façon idempotente.
do $$ begin
  alter table public.planning_entries add constraint planning_entries_owner_id_fkey foreign key (owner_id) references public.profiles(id);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.exchange_requests add constraint exchange_requests_from_id_fkey foreign key (from_id) references public.profiles(id);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.exchange_requests add constraint exchange_requests_to_id_fkey foreign key (to_id) references public.profiles(id);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.leave_requests add constraint leave_requests_owner_id_fkey foreign key (owner_id) references public.profiles(id);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.push_tokens add constraint push_tokens_owner_id_fkey foreign key (owner_id) references public.profiles(id) on delete cascade;
exception when duplicate_object then null; end $$;

alter table public.planning_entries alter column owner_id set not null;
alter table public.exchange_requests alter column from_id set not null;
alter table public.exchange_requests alter column to_id set not null;
alter table public.leave_requests alter column owner_id set not null;
alter table public.push_tokens alter column owner_id set not null;

create index if not exists planning_owner_id_date_idx on public.planning_entries(owner_id,date_str);
create index if not exists exchange_from_id_idx on public.exchange_requests(from_id,status);
create index if not exists exchange_to_id_idx on public.exchange_requests(to_id,status);
create index if not exists leave_owner_id_idx on public.leave_requests(owner_id,status);

-- ---------------------------------------------------------------------------
-- 3) Dates réelles + congés sur période
-- ---------------------------------------------------------------------------
alter table public.planning_entries alter column date_str type date using date_str::date;
alter table public.exchange_requests alter column date_str type date using date_str::date;
alter table public.exchange_requests alter column target_date_str type date using target_date_str::date;

alter table public.leave_requests add column if not exists start_date date;
alter table public.leave_requests add column if not exists end_date date;
update public.leave_requests
set start_date=coalesce(start_date,date_str::date),
    end_date=coalesce(end_date,date_str::date)
where start_date is null or end_date is null;
alter table public.leave_requests alter column start_date set not null;
alter table public.leave_requests alter column end_date set not null;

alter table public.planning_entries add column if not exists leave_request_id text references public.leave_requests(id);
update public.planning_entries p
set leave_request_id=l.id
from public.leave_requests l
where p.leave_request_id is null and l.planning_entry_id=p.id;
create index if not exists planning_leave_request_idx on public.planning_entries(leave_request_id);

-- L'ancienne unicité mono-date des demandes en attente ne suffit plus pour une période.
drop index if exists public.leave_pending_owner_date_uidx;

-- ---------------------------------------------------------------------------
-- 4) Journal d'audit immuable
-- ---------------------------------------------------------------------------
create table if not exists public.audit_log (
  id bigserial primary key,
  actor_id uuid references public.profiles(id),
  actor_name text not null,
  action text not null,
  entity_type text not null,
  entity_id text not null,
  subject_id uuid references public.profiles(id),
  subject_name text,
  reason text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists audit_created_idx on public.audit_log(created_at desc);
create index if not exists audit_subject_idx on public.audit_log(subject_id,created_at desc);
alter table public.audit_log enable row level security;
drop policy if exists audit_select on public.audit_log;
create policy audit_select on public.audit_log for select to authenticated using (public.is_admin());
revoke all on public.audit_log from anon, authenticated;
grant select on public.audit_log to authenticated;

create or replace function public.write_audit(
  p_action text,
  p_entity_type text,
  p_entity_id text,
  p_subject_id uuid default null,
  p_subject_name text default null,
  p_reason text default null,
  p_details jsonb default '{}'::jsonb
) returns void
language plpgsql security definer set search_path=public
as $$
declare actor_name_value text;
begin
  select trim(coalesce(prenom,'') || ' ' || coalesce(nom,'')) into actor_name_value
  from public.profiles where id=auth.uid();
  insert into public.audit_log(actor_id,actor_name,action,entity_type,entity_id,subject_id,subject_name,reason,details)
  values(auth.uid(),coalesce(nullif(actor_name_value,''),'Système'),p_action,p_entity_type,p_entity_id,p_subject_id,p_subject_name,p_reason,coalesce(p_details,'{}'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------------
-- 5) RLS : lecture utile, mutations officielles via RPC
-- ---------------------------------------------------------------------------
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated using (
  id=auth.uid()
  or public.is_admin()
  or (public.current_account_active() and account_status='active' and hospital=public.current_hospital())
);

drop policy if exists planning_select on public.planning_entries;
create policy planning_select on public.planning_entries for select to authenticated using (
  public.is_admin()
  or (public.current_account_active() and exists(
    select 1 from public.profiles p
    where p.id=planning_entries.owner_id
      and p.account_status='active'
      and p.hospital=public.current_hospital()
  ))
);

-- Plus de création/modification/suppression directe d'une garde officielle par un médecin.
drop policy if exists planning_insert on public.planning_entries;
drop policy if exists planning_update on public.planning_entries;
drop policy if exists planning_delete on public.planning_entries;
revoke insert,update,delete on public.planning_entries from authenticated;

-- Les congés passent par RPC afin de contrôler les périodes et l'identité.
drop policy if exists leave_insert on public.leave_requests;
revoke insert on public.leave_requests from authenticated;

drop policy if exists leave_select on public.leave_requests;
create policy leave_select on public.leave_requests for select to authenticated using (
  public.is_admin() or (public.current_account_active() and owner_id=auth.uid())
);

-- ---------------------------------------------------------------------------
-- 6) Validation / suspension d'un compte par un admin
-- ---------------------------------------------------------------------------
create or replace function public.review_profile_account(
  p_profile_id uuid,
  p_action text,
  p_hospital text default null,
  p_service text default null,
  p_medical_grade text default null
)
returns void
language plpgsql security definer set search_path=public
as $$
declare
  p public.profiles%rowtype;
  v_hospital text;
  v_service text;
  v_grade text;
begin
  if not public.is_admin() then raise exception 'Réservé à l’administrateur'; end if;
  if p_profile_id=auth.uid() then raise exception 'Impossible de modifier votre propre statut'; end if;
  select * into p from public.profiles where id=p_profile_id for update;
  if not found then raise exception 'Profil introuvable'; end if;

  if p_action='approve' then
    v_hospital:=trim(coalesce(nullif(p_hospital,''),p.hospital));
    v_service:=trim(coalesce(nullif(p_service,''),p.service));
    v_grade:=coalesce(nullif(p_medical_grade,''),p.medical_grade);
    if v_hospital='' or v_service='' then raise exception 'Établissement et service obligatoires'; end if;
    if v_grade not in ('junior','senior') then raise exception 'Grade médical invalide'; end if;
    update public.profiles
      set account_status='active',hospital=v_hospital,service=v_service,
          medical_grade=v_grade,fonction=v_grade
      where id=p_profile_id;
    perform public.write_audit(
      'account.approved','profile',p_profile_id::text,p.id,trim(p.prenom||' '||p.nom),null,
      jsonb_build_object('hospital',v_hospital,'service',v_service,'medical_grade',v_grade)
    );
  elsif p_action='suspend' then
    update public.profiles set account_status='suspended' where id=p_profile_id;
    perform public.write_audit('account.suspended','profile',p_profile_id::text,p.id,trim(p.prenom||' '||p.nom));
  else
    raise exception 'Action invalide';
  end if;
end;
$$;
grant execute on function public.review_profile_account(uuid,text,text,text,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 7) Affectation officielle par l'administration
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_planning(p_owner_id uuid,p_date date,p_shift_id text)
returns text
language plpgsql security definer set search_path=public
as $$
declare
  owner public.profiles%rowtype;
  existing public.planning_entries%rowtype;
  entry_id text;
begin
  if not public.is_admin() then raise exception 'Réservé à l’administrateur'; end if;
  if p_date < current_date then raise exception 'Une garde passée ne peut pas être créée ou modifiée'; end if;
  if p_shift_id not in ('service-jour','service-24h','service-nuit','urg-jour','urg-24h','urg-nuit') then
    raise exception 'Type de garde invalide';
  end if;

  select * into owner from public.profiles where id=p_owner_id and account_status='active';
  if not found then raise exception 'Médecin introuvable ou inactif'; end if;

  if exists(
    select 1 from public.leave_requests l
    where l.owner_id=p_owner_id and l.status='approved' and p_date between l.start_date and l.end_date
  ) then raise exception 'Ce médecin est en congé approuvé à cette date'; end if;

  select * into existing from public.planning_entries
  where owner_id=p_owner_id and date_str=p_date and deleted_at is null
  for update;

  if found then
    if existing.shift_id='conge' then raise exception 'Ce jour est couvert par un congé approuvé'; end if;
    update public.planning_entries set shift_id=p_shift_id where id=existing.id;
    entry_id:=existing.id;
  else
    entry_id:='p-'||replace(gen_random_uuid()::text,'-','');
    insert into public.planning_entries(id,date_str,shift_id,owner_id,owner_phone,owner_name,created_at)
    values(entry_id,p_date,p_shift_id,owner.id,owner.phone,trim(owner.prenom||' '||owner.nom),now());
  end if;

  perform public.write_audit(
    'planning.assigned','planning_entry',entry_id,owner.id,trim(owner.prenom||' '||owner.nom),null,
    jsonb_build_object('date',p_date,'shift_id',p_shift_id)
  );
  return entry_id;
end;
$$;
grant execute on function public.admin_set_planning(uuid,date,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 8) Congés : demande de période puis validation par un autre admin
-- ---------------------------------------------------------------------------
create or replace function public.create_leave_request(p_request_id text,p_start_date date,p_end_date date)
returns void
language plpgsql security definer set search_path=public
as $$
declare me public.profiles%rowtype;
begin
  select * into me from public.profiles where id=auth.uid();
  if not found or me.account_status<>'active' then raise exception 'Compte non actif'; end if;
  if p_start_date < current_date then raise exception 'Une demande ne peut pas commencer dans le passé'; end if;
  if p_end_date < p_start_date then raise exception 'Période invalide'; end if;
  if (p_end_date-p_start_date) > 365 then raise exception 'Période trop longue'; end if;

  if exists(
    select 1 from public.leave_requests l
    where l.owner_id=me.id
      and l.status in ('pendingAdmin','approved')
      and daterange(l.start_date,l.end_date,'[]') && daterange(p_start_date,p_end_date,'[]')
  ) then raise exception 'Une demande de congé existe déjà sur cette période'; end if;

  insert into public.leave_requests(
    id,date_str,start_date,end_date,owner_id,owner_phone,owner_name,status,created_at
  ) values (
    p_request_id,p_start_date::text,p_start_date,p_end_date,me.id,me.phone,trim(me.prenom||' '||me.nom),'pendingAdmin',now()
  );
  perform public.write_audit('leave.created','leave_request',p_request_id,me.id,trim(me.prenom||' '||me.nom),null,
    jsonb_build_object('start_date',p_start_date,'end_date',p_end_date));
end;
$$;
grant execute on function public.create_leave_request(text,date,date) to authenticated;

create or replace function public.cancel_leave_request(p_request_id text)
returns void
language plpgsql security definer set search_path=public
as $$
declare r public.leave_requests%rowtype;
begin
  select * into r from public.leave_requests where id=p_request_id for update;
  if not found then raise exception 'Demande de congé introuvable'; end if;
  if r.owner_id<>auth.uid() or r.status<>'pendingAdmin' then raise exception 'Annulation non autorisée'; end if;
  update public.leave_requests set status='cancelled',reviewed_at=now() where id=p_request_id;
  perform public.write_audit('leave.cancelled','leave_request',p_request_id,r.owner_id,r.owner_name);
end;
$$;

grant execute on function public.cancel_leave_request(text) to authenticated;

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

  if p_action='reject' then
    update public.leave_requests set status='rejectedAdmin',reviewed_at=now() where id=p_request_id;
    perform public.write_audit('leave.rejected','leave_request',p_request_id,r.owner_id,r.owner_name);
    return;
  elsif p_action<>'approve' then
    raise exception 'Action invalide';
  end if;

  select string_agg(to_char(p.date_str,'DD/MM/YYYY'),', ' order by p.date_str)
  into conflict_dates
  from public.planning_entries p
  where p.owner_id=r.owner_id and p.deleted_at is null and p.shift_id<>'conge'
    and p.date_str between r.start_date and r.end_date;
  if conflict_dates is not null then
    raise exception 'Gardes à couvrir avant approbation : %', conflict_dates;
  end if;

  perform set_config('huim6.review_request','1',true);
  insert into public.planning_entries(id,date_str,shift_id,owner_id,owner_phone,owner_name,leave_request_id,created_at)
  select 'leave-'||replace(gen_random_uuid()::text,'-',''), d::date, 'conge', r.owner_id, r.owner_phone, r.owner_name, r.id, now()
  from generate_series(r.start_date::timestamp,r.end_date::timestamp,interval '1 day') d
  order by d;

  select id into first_entry from public.planning_entries
  where leave_request_id=r.id and deleted_at is null order by date_str limit 1;

  update public.leave_requests
  set status='approved',planning_entry_id=first_entry,reviewed_at=now()
  where id=p_request_id;
  perform public.write_audit('leave.approved','leave_request',p_request_id,r.owner_id,r.owner_name,null,
    jsonb_build_object('start_date',r.start_date,'end_date',r.end_date));
end;
$$;
grant execute on function public.review_leave_request(text,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 9) Suppression admin avec motif obligatoire et archivage cohérent
-- ---------------------------------------------------------------------------
drop function if exists public.admin_delete_planning(text);
create or replace function public.admin_delete_planning(p_entry_id text,p_reason text)
returns void
language plpgsql security definer set search_path=public
as $$
declare e public.planning_entries%rowtype;
begin
  if not public.is_admin() then raise exception 'Réservé à l’administrateur'; end if;
  if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Motif de suppression obligatoire'; end if;

  select * into e from public.planning_entries where id=p_entry_id and deleted_at is null for update;
  if not found then raise exception 'Affectation introuvable'; end if;

  perform set_config('huim6.review_request','1',true);
  update public.exchange_requests set status='cancelled'
  where status in ('pendingB','pendingAdmin')
    and (planning_entry_id=p_entry_id or target_planning_entry_id=p_entry_id);

  if e.shift_id='conge' and e.leave_request_id is not null then
    update public.planning_entries set deleted_at=now()
    where leave_request_id=e.leave_request_id and deleted_at is null;
    update public.leave_requests set status='cancelled',reviewed_at=now()
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
grant execute on function public.admin_delete_planning(text,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 10) Échanges/transferts : identité UUID, dates futures et aucun auto-contrôle
-- ---------------------------------------------------------------------------
create or replace function public.guard_has_started(p_date date,p_shift_id text)
returns boolean language sql stable set search_path=public as $$
  select case
    when p_shift_id in ('service-jour','service-24h','urg-jour','urg-24h')
      then timezone('Africa/Casablanca',now()) >= (p_date::timestamp + time '08:00')
    when p_shift_id in ('service-nuit','urg-nuit')
      then timezone('Africa/Casablanca',now()) >= (p_date::timestamp + time '20:00')
    else true
  end
$$;

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

  -- L'identité du demandeur vient exclusivement de la session Auth.
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
  if public.guard_has_started(source.date_str,source.shift_id) then raise exception 'La garde source est déjà commencée ou passée'; end if;
  new.date_str:=source.date_str;
  new.shift_id:=source.shift_id;

  if new.type='exchange' then
    if new.target_planning_entry_id is null then raise exception 'Garde cible obligatoire'; end if;
    select * into target from public.planning_entries
    where id=new.target_planning_entry_id and owner_id=to_profile.id and deleted_at is null;
    if not found or target.shift_id='conge' then raise exception 'Garde cible invalide'; end if;
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

drop policy if exists exchange_insert on public.exchange_requests;
create policy exchange_insert on public.exchange_requests for insert to authenticated with check (
  public.current_account_active()
  and from_id=auth.uid()
  and from_id<>to_id
  and status='pendingB'
  and exists(
    select 1 from public.profiles a join public.profiles b on true
    where a.id=exchange_requests.from_id and b.id=exchange_requests.to_id
      and a.account_status='active' and b.account_status='active'
      and a.hospital=b.hospital
  )
  and exists(
    select 1 from public.planning_entries s
    where s.id=exchange_requests.planning_entry_id
      and s.owner_id=exchange_requests.from_id
      and s.deleted_at is null and s.shift_id<>'conge'
      and s.date_str=exchange_requests.date_str and s.shift_id=exchange_requests.shift_id
      and not public.guard_has_started(s.date_str,s.shift_id)
  )
  and (
    type='transfer' or (
      type='exchange' and exists(
        select 1 from public.planning_entries t
        where t.id=exchange_requests.target_planning_entry_id
          and t.owner_id=exchange_requests.to_id
          and t.deleted_at is null and t.shift_id<>'conge'
          and t.date_str=exchange_requests.target_date_str and t.shift_id=exchange_requests.target_shift_id
          and not public.guard_has_started(t.date_str,t.shift_id)
      )
    )
  )
);

drop policy if exists exchange_select on public.exchange_requests;
create policy exchange_select on public.exchange_requests for select to authenticated using (
  public.is_admin() or (public.current_account_active() and (from_id=auth.uid() or to_id=auth.uid()))
);

create or replace function public.respond_shift_request(p_request_id text,p_action text)
returns void language plpgsql security definer set search_path=public
as $$
declare r public.exchange_requests%rowtype;
begin
  select * into r from public.exchange_requests where id=p_request_id for update;
  if not found then raise exception 'Demande introuvable'; end if;
  if r.to_id<>auth.uid() then raise exception 'Non autorisé'; end if;
  if r.status<>'pendingB' then raise exception 'Demande déjà traitée'; end if;
  if not public.current_account_active() then raise exception 'Compte actif requis'; end if;
  if not exists(
    select 1 from public.planning_entries s
    where s.id=r.planning_entry_id and s.owner_id=r.from_id and s.deleted_at is null
      and s.shift_id<>'conge' and s.date_str=r.date_str and s.shift_id=r.shift_id
      and not public.guard_has_started(s.date_str,s.shift_id)
  ) then raise exception 'La garde source a été modifiée, supprimée ou a déjà commencé'; end if;
  if r.type='exchange' and not exists(
    select 1 from public.planning_entries t
    where t.id=r.target_planning_entry_id and t.owner_id=r.to_id and t.deleted_at is null
      and t.shift_id<>'conge' and t.date_str=r.target_date_str and t.shift_id=r.target_shift_id
      and not public.guard_has_started(t.date_str,t.shift_id)
  ) then raise exception 'La garde cible a été modifiée, supprimée ou a déjà commencé'; end if;
  if p_action='accept' then
    update public.exchange_requests set status='pendingAdmin' where id=p_request_id;
    perform public.write_audit('exchange.accepted','exchange_request',p_request_id,r.to_id,r.to_name);
  elsif p_action='decline' then
    update public.exchange_requests set status='declinedB' where id=p_request_id;
    perform public.write_audit('exchange.declined','exchange_request',p_request_id,r.to_id,r.to_name);
  else raise exception 'Action invalide';
  end if;
end;
$$;

create or replace function public.cancel_shift_request(p_request_id text)
returns void language plpgsql security definer set search_path=public
as $$
declare r public.exchange_requests%rowtype;
begin
  select * into r from public.exchange_requests where id=p_request_id for update;
  if not found then raise exception 'Demande introuvable'; end if;
  if r.from_id<>auth.uid() or r.status<>'pendingB' then raise exception 'Non autorisé'; end if;
  update public.exchange_requests set status='cancelled' where id=p_request_id;
  perform public.write_audit('exchange.cancelled','exchange_request',p_request_id,r.from_id,r.from_name);
end;
$$;

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
  if auth.uid()=r.from_id or auth.uid()=r.to_id then raise exception 'Un administrateur participant ne peut pas valider sa propre demande'; end if;

  if p_action='reject' then
    update public.exchange_requests set status='rejectedAdmin' where id=p_request_id;
    perform public.write_audit('exchange.rejected','exchange_request',p_request_id,null,null);
    return;
  elsif p_action<>'approve' then raise exception 'Action invalide'; end if;

  select hospital into from_hospital from public.profiles where id=r.from_id and account_status='active';
  select hospital into to_hospital from public.profiles where id=r.to_id and account_status='active';
  if from_hospital is null or to_hospital is null or from_hospital is distinct from to_hospital then
    raise exception 'Participants invalides ou inter-établissements';
  end if;
  select * into source from public.planning_entries where id=r.planning_entry_id and deleted_at is null for update;
  if not found or source.owner_id<>r.from_id or source.shift_id='conge'
     or source.date_str<>r.date_str or source.shift_id<>r.shift_id then raise exception 'Garde source modifiée'; end if;
  if public.guard_has_started(source.date_str,source.shift_id) then raise exception 'La garde source est déjà commencée ou passée'; end if;

  perform set_config('huim6.review_request','1',true);
  if r.type='transfer' then
    if exists(select 1 from public.planning_entries where owner_id=r.to_id and date_str=source.date_str and deleted_at is null) then
      raise exception 'Le destinataire a déjà une affectation ce jour-là';
    end if;
    update public.planning_entries
      set owner_id=r.to_id,owner_phone=r.to_phone,owner_name=r.to_name
      where id=source.id;
  else
    select * into target from public.planning_entries where id=r.target_planning_entry_id and deleted_at is null for update;
    if not found or target.owner_id<>r.to_id or target.shift_id='conge'
       or target.date_str<>r.target_date_str or target.shift_id<>r.target_shift_id then raise exception 'Garde cible modifiée'; end if;
    if public.guard_has_started(target.date_str,target.shift_id) then raise exception 'La garde cible est déjà commencée ou passée'; end if;
    if source.date_str=target.date_str then
      update public.planning_entries set shift_id=target.shift_id where id=source.id;
      update public.planning_entries set shift_id=source.shift_id where id=target.id;
    else
      if exists(select 1 from public.planning_entries where owner_id=r.to_id and date_str=source.date_str and deleted_at is null and id<>target.id) then
        raise exception 'Conflit de planning du destinataire';
      end if;
      if exists(select 1 from public.planning_entries where owner_id=r.from_id and date_str=target.date_str and deleted_at is null and id<>source.id) then
        raise exception 'Conflit de planning du demandeur';
      end if;
      update public.planning_entries set date_str=target.date_str,shift_id=target.shift_id where id=source.id;
      update public.planning_entries set date_str=source.date_str,shift_id=source.shift_id where id=target.id;
    end if;
  end if;

  update public.exchange_requests set status='approved' where id=p_request_id;
  perform public.write_audit('exchange.approved','exchange_request',p_request_id,null,null);
end;
$$;

grant execute on function public.respond_shift_request(text,text) to authenticated;
grant execute on function public.cancel_shift_request(text) to authenticated;
grant execute on function public.review_shift_request(text,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 11) Push tokens liés aussi à l'UUID utilisateur
-- ---------------------------------------------------------------------------
create or replace function public.register_push_token(p_token text,p_platform text default 'web')
returns void language plpgsql security definer set search_path=public as $$
declare p public.profiles%rowtype;
begin
  select * into p from public.profiles where id=auth.uid() and account_status='active';
  if not found then raise exception 'Profil actif introuvable'; end if;
  if coalesce(trim(p_token),'')='' then raise exception 'Token push vide'; end if;
  insert into public.push_tokens(token,owner_id,owner_phone,platform,created_at,updated_at)
  values(p_token,p.id,p.phone,coalesce(nullif(p_platform,''),'web'),now(),now())
  on conflict(token) do update set owner_id=excluded.owner_id,owner_phone=excluded.owner_phone,platform=excluded.platform,updated_at=now();
end;
$$;

create or replace function public.unregister_push_token(p_token text)
returns void language plpgsql security definer set search_path=public as $$
begin
  delete from public.push_tokens where token=p_token and owner_id=auth.uid();
end;
$$;
grant execute on function public.unregister_push_token(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 12) Realtime profils pour validation admin
-- ---------------------------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.profiles;
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 13) Droits d'exécution explicites des fonctions SECURITY DEFINER
-- ---------------------------------------------------------------------------
revoke all on function public.write_audit(text,text,text,uuid,text,text,jsonb) from public,anon,authenticated;
revoke all on function public.review_profile_account(uuid,text,text,text,text) from public,anon;
revoke all on function public.admin_set_planning(uuid,date,text) from public,anon;
revoke all on function public.create_leave_request(text,date,date) from public,anon;
revoke all on function public.cancel_leave_request(text) from public,anon;
revoke all on function public.review_leave_request(text,text) from public,anon;
revoke all on function public.admin_delete_planning(text,text) from public,anon;
revoke all on function public.respond_shift_request(text,text) from public,anon;
revoke all on function public.cancel_shift_request(text) from public,anon;
revoke all on function public.review_shift_request(text,text) from public,anon;
revoke all on function public.register_push_token(text,text) from public,anon;
revoke all on function public.unregister_push_token(text) from public,anon;
revoke all on function public.is_admin() from public,anon;
revoke all on function public.current_profile_id() from public,anon;
revoke all on function public.current_account_active() from public,anon;
revoke all on function public.current_hospital() from public,anon;
revoke all on function public.current_phone() from public,anon;

grant execute on function public.is_admin() to authenticated;
grant execute on function public.current_profile_id() to authenticated;
grant execute on function public.current_account_active() to authenticated;
grant execute on function public.current_hospital() to authenticated;
grant execute on function public.current_phone() to authenticated;

-- Vérifications utiles après migration :
-- select id,prenom,nom,medical_grade,role,account_status from public.profiles order by created_at;
-- select owner_id,owner_phone,date_str,shift_id from public.planning_entries where deleted_at is null order by date_str;
