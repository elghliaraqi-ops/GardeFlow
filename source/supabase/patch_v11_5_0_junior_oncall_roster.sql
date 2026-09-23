-- GardeFlow V11.5.0
-- Vue réseau en lecture seule : Juniors d'astreinte.
-- Retourne uniquement les gardes de SERVICE des Juniors, pour des mois validés.
-- N'ouvre pas les brouillons ni les autres types de garde.

create or replace function public.junior_oncall_roster(
  p_from date,
  p_to date
)
returns table(
  date_str date,
  shift_id text,
  owner_name text,
  service text,
  hospital text
)
language sql
stable
security definer
set search_path=public
as $$
  select
    pe.date_str,
    pe.shift_id,
    pe.owner_name,
    pr.service,
    pr.hospital
  from public.planning_entries pe
  join public.profiles pr on pr.id=pe.owner_id
  where auth.uid() is not null
    and public.current_account_active()
    and p_from is not null
    and p_to is not null
    and p_from <= p_to
    and pe.deleted_at is null
    and pe.date_str between p_from and p_to
    and pe.shift_id in ('service-jour','service-24h','service-nuit')
    and pr.account_status='active'
    and pr.medical_grade='junior'
    and public.planning_month_is_approved(pe.owner_id, pe.date_str)
  order by pe.date_str, pr.hospital, pr.service, pe.owner_name;
$$;

revoke all on function public.junior_oncall_roster(date,date) from public,anon;
grant execute on function public.junior_oncall_roster(date,date) to authenticated;

-- Test facultatif depuis une session authentifiée :
-- select * from public.junior_oncall_roster(current_date, current_date + 31);
