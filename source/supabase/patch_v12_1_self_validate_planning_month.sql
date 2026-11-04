-- GardeFlow V12.1 - validation directe du mois par son propriétaire.
-- Exécuter dans le projet Supabase PlanningHM6 de GardeFlow.
-- Un mois validé devient immédiatement officiel et verrouillé.
-- Les demandes de congé continuent à être approuvées séparément.

alter table public.planning_months
  drop constraint if exists planning_months_approval_source_check;
alter table public.planning_months
  add constraint planning_months_approval_source_check
  check (approval_source is null or approval_source in ('admin','automatic','legacy','self'));

create or replace function public.submit_my_planning_month(p_year integer, p_month integer)
returns text[]
language plpgsql
security definer
set search_path to ''
as $function$
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
  -- La fonction ne peut valider que le planning du médecin connecté.
  select * into me from public.profiles
  where id=(select auth.uid()) and account_status='active';
  if not found then raise exception 'Compte actif requis'; end if;
  if p_year not between 2020 and 2100 or p_month not between 1 and 12 then
    raise exception 'Mois invalide';
  end if;
  first_day:=make_date(p_year,p_month,1);
  last_day:=(first_day + interval '1 month - 1 day')::date;
  if first_day < date_trunc('month',current_date)::date then
    raise exception 'Un mois passé ne peut plus être validé';
  end if;

  select status into current_state from public.planning_months
  where owner_id=me.id and year=p_year and month=p_month for update;
  if current_state='approved' then
    raise exception 'Calendrier déjà validé définitivement';
  end if;
  -- Les mois "submitted" créés par les anciennes versions peuvent
  -- être finalisés directement par le médecin, sans validation admin.

  -- Associer les tuiles Congé aux demandes déjà existantes.
  update public.planning_entries p set leave_request_id=(
    select l.id from public.leave_requests l
    where l.owner_id=me.id and l.status in ('pendingAdmin','approved')
      and p.date_str between l.start_date and l.end_date
    order by l.created_at desc limit 1)
  where p.owner_id=me.id and p.deleted_at is null and p.shift_id='conge'
    and p.date_str between first_day and last_day and p.leave_request_id is null
    and exists(select 1 from public.leave_requests l
      where l.owner_id=me.id and l.status in ('pendingAdmin','approved')
        and p.date_str between l.start_date and l.end_date);

  -- Les congés contigus sans demande deviennent des demandes séparées.
  for range_rec in
    with conge_days as (
      select p.date_str,p.date_str-(row_number() over(order by p.date_str))::int as grp
      from public.planning_entries p
      where p.owner_id=me.id and p.deleted_at is null and p.shift_id='conge'
        and p.leave_request_id is null and p.date_str between first_day and last_day)
    select min(date_str)::date as start_date,max(date_str)::date as end_date
    from conge_days group by grp order by min(date_str)
  loop
    request_id:='lr-'||replace(gen_random_uuid()::text,'-','');
    insert into public.leave_requests(id,date_str,start_date,end_date,owner_id,owner_phone,owner_name,status,created_at)
    values(request_id,range_rec.start_date::text,range_rec.start_date,range_rec.end_date,
      me.id,me.phone,trim(me.prenom||' '||me.nom),'pendingAdmin',now());
    update public.planning_entries set leave_request_id=request_id
    where owner_id=me.id and deleted_at is null and shift_id='conge'
      and leave_request_id is null and date_str between range_rec.start_date and range_rec.end_date;
    select id into first_entry from public.planning_entries
    where owner_id=me.id and deleted_at is null and leave_request_id=request_id
    order by date_str limit 1;
    update public.leave_requests set planning_entry_id=first_entry where id=request_id;
    created_leave_ids:=array_append(created_leave_ids,request_id);
    perform public.write_audit('leave.created','leave_request',request_id,
      me.id,trim(me.prenom||' '||me.nom),null,
      jsonb_build_object('start_date',range_rec.start_date,'end_date',range_rec.end_date,'source','planning_tile'));
  end loop;

  -- La validation du médecin est la validation finale, y compris pour un mois vide.
  insert into public.planning_months(owner_id,year,month,status,submitted_at,reviewed_at,reviewed_by,
    rejection_reason,updated_at,auto_validation_blocked,approval_source)
  values(me.id,p_year,p_month,'approved',now(),now(),me.id,null,now(),false,'self')
  on conflict(owner_id,year,month) do update
    set status='approved',
        submitted_at=coalesce(public.planning_months.submitted_at,now()),
        reviewed_at=now(),reviewed_by=me.id,
        rejection_reason=null,updated_at=now(),
        auto_validation_blocked=false,approval_source='self'
    where public.planning_months.status in ('draft','rejected','submitted');

  perform public.write_audit('planning_month.self_approved','planning_month',
    me.id::text||':'||p_year||':'||p_month,
    me.id,trim(me.prenom||' '||me.nom),null,
    jsonb_build_object('year',p_year,'month',p_month,'approval_source','self'));
  return created_leave_ids;
end;
$function$;

revoke all on function public.submit_my_planning_month(integer,integer)
  from public,anon;
grant execute on function public.submit_my_planning_month(integer,integer)
  to authenticated;

-- Plus d'approbation ou de rejet de plannings par un administrateur.
-- L'administration peut toujours rouvrir un mois approuvé, avec motif.
revoke execute on function public.review_planning_month(uuid,integer,integer,text,text)
  from public,anon,authenticated;

-- Les anciennes soumissions sont des confirmations du propriétaire.
-- Les mois déjà passés sont uniquement régularisés par cette migration ;
-- aucune garde, aucun congé et aucun échange n'est supprimé.
do $backfill$
declare
  rec record;
begin
  for rec in
    select pm.owner_id,pm.year,pm.month,p.prenom,p.nom
    from public.planning_months pm
    join public.profiles p on p.id=pm.owner_id
    where pm.status='submitted'
  loop
    update public.planning_months
       set status='approved',reviewed_at=now(),reviewed_by=rec.owner_id,
           approval_source='self',auto_validation_blocked=false,
           rejection_reason=null,updated_at=now()
    where owner_id=rec.owner_id and year=rec.year and month=rec.month
      and status='submitted';
    perform public.write_audit('planning_month.self_approved_migration','planning_month',
      rec.owner_id::text||':'||rec.year||':'||rec.month,
      rec.owner_id,trim(coalesce(rec.prenom,'')||' '||coalesce(rec.nom,'')),
      'Ancienne soumission régularisée après suppression de la double validation',
      jsonb_build_object('year',rec.year,'month',rec.month,'approval_source','self','migration',true));
  end loop;
end;
$backfill$;
