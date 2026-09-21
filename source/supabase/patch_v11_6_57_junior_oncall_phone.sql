-- GardeFlow V11.6.57
-- Expose le numéro de téléphone dans la liste réseau des Juniors d'astreinte
-- afin que l'application puisse ouvrir directement le composeur téléphonique.

drop function if exists public.junior_oncall_roster(date,date);

create function public.junior_oncall_roster(
  p_from date,
  p_to date
)
returns table(
  date_str date,
  shift_id text,
  owner_name text,
  owner_phone text,
  service text,
  hospital text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    pe.date_str,
    pe.shift_id,
    pe.owner_name,
    pr.phone as owner_phone,
    case
      when pe.shift_id like 'urg-%' then 'Urgences'
      else pr.service
    end as service,
    pr.hospital
  from public.planning_entries pe
  join public.profiles pr on pr.id = pe.owner_id
  where auth.uid() is not null
    and public.current_account_active()
    and p_from is not null
    and p_to is not null
    and p_from <= p_to
    and pe.deleted_at is null
    and pe.date_str between p_from and p_to
    and pe.shift_id in (
      'service-jour','service-24h','service-nuit',
      'urg-jour','urg-24h','urg-nuit'
    )
    and pr.account_status = 'active'
    and pr.medical_grade = 'junior'
    and (
      (
        pe.shift_id like 'service-%'
        and public.planning_month_is_approved(pe.owner_id, pe.date_str)
      )
      or
      (
        pe.shift_id like 'urg-%'
        and (
          pe.source_type = 'official_emergency'
          or public.planning_month_is_approved(pe.owner_id, pe.date_str)
        )
      )
    )
  order by
    pe.date_str,
    pr.hospital,
    case when pe.shift_id like 'urg-%' then 0 else 1 end,
    case
      when pe.shift_id like 'urg-%' then 'Urgences'
      else pr.service
    end,
    pe.owner_name;
$$;

grant execute on function public.junior_oncall_roster(date,date)
  to authenticated;
