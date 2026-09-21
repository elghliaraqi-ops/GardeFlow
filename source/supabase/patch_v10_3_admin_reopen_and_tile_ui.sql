-- HUIM6 Planning V10.3 — dévalidation admin d'un calendrier validé
--
-- À exécuter UNE FOIS après patch_v10_2_self_validation_tiles_notifications.sql.
-- Aucune mise à jour de la Edge Function send-push n'est nécessaire pour V10.3.
--
-- Règles :
-- 1) seul profiles.role='admin' donne les droits administrateur ; le grade junior/senior
--    n'entre jamais dans les contrôles d'autorisation ;
-- 2) un admin peut rouvrir le calendrier validé d'un autre médecin, quel que soit son grade ;
-- 3) l'admin ne peut pas rouvrir son propre calendrier : un autre admin doit le faire ;
-- 4) le médecin retrouve alors ses tuiles et doit valider à nouveau le mois ;
-- 5) les transferts/échanges actifs du mois sont annulés lors de la réouverture ;
-- 6) les congés encore en attente du mois sont annulés et redeviendront des demandes
--    lors de la prochaine validation ;
-- 7) un congé déjà approuvé reste protégé et seul un admin peut le supprimer.

-- ---------------------------------------------------------------------------
-- 1) RPC admin : dévalider / rouvrir un mois
-- ---------------------------------------------------------------------------
create or replace function public.admin_reopen_planning_month(
  p_owner_id uuid,
  p_year int,
  p_month int,
  p_reason text
)
returns void
language plpgsql security definer set search_path=public
as $$
declare
  target_profile public.profiles%rowtype;
  month_state text;
  first_day date;
  last_day date;
  pending_leave_ids text[] := array[]::text[];
  cancelled_exchange_count int := 0;
  cancelled_leave_count int := 0;
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;
  if p_owner_id=auth.uid() then
    raise exception 'Un administrateur ne peut pas dévalider son propre calendrier : un autre administrateur doit le faire';
  end if;
  if length(trim(coalesce(p_reason,'')))<3 then
    raise exception 'Motif de dévalidation obligatoire';
  end if;
  if p_year not between 2020 and 2100 or p_month not between 1 and 12 then
    raise exception 'Mois invalide';
  end if;

  first_day:=make_date(p_year,p_month,1);
  last_day:=(first_day + interval '1 month - 1 day')::date;
  if first_day < date_trunc('month',current_date)::date then
    raise exception 'Un calendrier d’un mois passé ne peut pas être rouvert';
  end if;

  select * into target_profile
  from public.profiles
  where id=p_owner_id and account_status='active';
  if not found then raise exception 'Médecin introuvable ou inactif'; end if;

  select status into month_state
  from public.planning_months
  where owner_id=p_owner_id and year=p_year and month=p_month
  for update;
  if not found or month_state<>'approved' then
    raise exception 'Ce calendrier n’est pas validé';
  end if;

  -- L'opération administrative est autorisée à libérer les références des demandes.
  perform set_config('huim6.review_request','1',true);

  -- Une garde redevenue modifiable ne doit rester engagée dans aucune demande active.
  update public.exchange_requests r
     set status='cancelled'
   where r.status in ('pendingB','pendingAdmin')
     and (
       r.planning_entry_id in (
         select p.id from public.planning_entries p
         where p.owner_id=p_owner_id
           and p.deleted_at is null
           and p.date_str between first_day and last_day
       )
       or r.target_planning_entry_id in (
         select p.id from public.planning_entries p
         where p.owner_id=p_owner_id
           and p.deleted_at is null
           and p.date_str between first_day and last_day
       )
     );
  get diagnostics cancelled_exchange_count = row_count;

  -- Les congés seulement EN ATTENTE, créés à partir des tuiles de ce mois,
  -- sont annulés. Les congés déjà approuvés restent intacts et protégés.
  select coalesce(array_agg(distinct l.id),'{}'::text[])
    into pending_leave_ids
  from public.leave_requests l
  join public.planning_entries p on p.leave_request_id=l.id
  where l.owner_id=p_owner_id
    and l.status='pendingAdmin'
    and p.owner_id=p_owner_id
    and p.deleted_at is null
    and p.shift_id='conge'
    and p.date_str between first_day and last_day;

  cancelled_leave_count:=coalesce(cardinality(pending_leave_ids),0);

  if cancelled_leave_count>0 then
    update public.leave_requests
       set status='cancelled', reviewed_at=now()
     where id=any(pending_leave_ids);

    update public.planning_entries
       set leave_request_id=null
     where owner_id=p_owner_id
       and deleted_at is null
       and date_str between first_day and last_day
       and leave_request_id=any(pending_leave_ids);
  end if;

  update public.planning_months
     set status='draft',
         submitted_at=null,
         reviewed_at=now(),
         reviewed_by=auth.uid(),
         rejection_reason=trim(p_reason),
         updated_at=now()
   where owner_id=p_owner_id and year=p_year and month=p_month;

  perform public.write_audit(
    'planning_month.reopened',
    'planning_month',
    p_owner_id::text||':'||p_year||':'||p_month,
    p_owner_id,
    trim(target_profile.prenom||' '||target_profile.nom),
    trim(p_reason),
    jsonb_build_object(
      'year',p_year,
      'month',p_month,
      'cancelled_active_exchange_requests',cancelled_exchange_count,
      'cancelled_pending_leave_requests',cancelled_leave_count
    )
  );
end;
$$;

revoke all on function public.admin_reopen_planning_month(uuid,integer,integer,text) from public,anon;
grant execute on function public.admin_reopen_planning_month(uuid,integer,integer,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2) Après réouverture, un congé DÉJÀ APPROUVÉ reste verrouillé côté serveur.
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
    if existing.shift_id='conge' and existing.leave_request_id is not null and exists(
      select 1 from public.leave_requests l
      where l.id=existing.leave_request_id and l.status='approved'
    ) then
      raise exception 'Ce congé a déjà été approuvé : seul un administrateur peut le supprimer';
    end if;

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

  if e.shift_id='conge' and e.leave_request_id is not null and exists(
    select 1 from public.leave_requests l
    where l.id=e.leave_request_id and l.status='approved'
  ) then
    raise exception 'Ce congé a déjà été approuvé : seul un administrateur peut le supprimer';
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
-- 3) Un congé approuvé reste supprimable par l'admin même si le mois a été
--    rouvert. Pour toutes les autres gardes, la suppression admin reste réservée
--    aux calendriers actuellement validés.
-- ---------------------------------------------------------------------------
create or replace function public.admin_delete_planning(p_entry_id text,p_reason text)
returns void
language plpgsql security definer set search_path=public
as $$
declare
  e public.planning_entries%rowtype;
  approved_leave boolean:=false;
begin
  if not public.is_admin() then raise exception 'Réservé à l’administrateur'; end if;
  if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Motif de suppression obligatoire'; end if;

  select * into e
  from public.planning_entries
  where id=p_entry_id and deleted_at is null
  for update;
  if not found then raise exception 'Affectation introuvable'; end if;

  if e.shift_id='conge' and e.leave_request_id is not null then
    select exists(
      select 1 from public.leave_requests l
      where l.id=e.leave_request_id and l.status='approved'
    ) into approved_leave;
  end if;

  if not public.planning_month_is_approved(e.owner_id,e.date_str) and not approved_leave then
    raise exception 'Seules les affectations d’un calendrier validé peuvent être supprimées par l’administrateur';
  end if;

  if e.shift_id='conge' and e.leave_request_id is not null and not approved_leave then
    raise exception 'Ce congé est encore en attente : utilisez Approuver ou Refuser';
  end if;

  perform set_config('huim6.review_request','1',true);

  update public.exchange_requests
     set status='cancelled'
   where status in ('pendingB','pendingAdmin')
     and (planning_entry_id=p_entry_id or target_planning_entry_id=p_entry_id);

  if approved_leave then
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
