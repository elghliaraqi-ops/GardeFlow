-- GardeFlow V11.1.6 — un administrateur peut dévalider son propre calendrier
--
-- À exécuter UNE FOIS après patch_v11_1_5_exchange_scope_rules.sql.
-- Aucune mise à jour de la Edge Function send-push n'est nécessaire.
--
-- Règles conservées :
-- - seul profiles.role='admin' donne les droits administrateur ; Junior/Senior n'accorde aucun droit ;
-- - le mois doit être validé et ne peut pas être un mois passé ;
-- - la réouverture annule les demandes de transfert/échange actives qui concernent le mois ;
-- - les congés encore en attente sont annulés et seront recréés à la prochaine validation ;
-- - les congés déjà approuvés restent protégés ; un admin peut les supprimer via l'action admin dédiée ;
-- - NOUVEAU : p_owner_id peut être auth.uid(), donc l'admin peut rouvrir son propre mois.

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
  self_reopen boolean := false;
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;
  if length(trim(coalesce(p_reason,'')))<3 then
    raise exception 'Motif de dévalidation obligatoire';
  end if;
  if p_year not between 2020 and 2100 or p_month not between 1 and 12 then
    raise exception 'Mois invalide';
  end if;

  self_reopen := (p_owner_id = auth.uid());
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

  -- Les congés seulement EN ATTENTE du mois sont annulés.
  -- Les congés déjà approuvés restent intacts et protégés.
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
      'self_reopen',self_reopen,
      'cancelled_active_exchange_requests',cancelled_exchange_count,
      'cancelled_pending_leave_requests',cancelled_leave_count
    )
  );
end;
$$;

revoke all on function public.admin_reopen_planning_month(uuid,integer,integer,text) from public,anon;
grant execute on function public.admin_reopen_planning_month(uuid,integer,integer,text) to authenticated;
