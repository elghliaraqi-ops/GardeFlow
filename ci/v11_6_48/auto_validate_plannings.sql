-- GardeFlow V11.6.48 — validation automatique des plannings 7 jours après le PDF officiel

create table if not exists public.planning_auto_validation_config (
  id boolean primary key default true check (id),
  sync_key uuid not null default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.planning_auto_validation_config(id)
values (true)
on conflict (id) do nothing;

alter table public.planning_auto_validation_config enable row level security;
revoke all on table public.planning_auto_validation_config from public, anon, authenticated;

create table if not exists public.planning_auto_validation_events (
  id uuid primary key default gen_random_uuid(),
  resource_id uuid not null references public.shared_resources(id) on delete cascade,
  resource_updated_at timestamptz not null,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  year integer not null check (year between 2020 and 2100),
  month integer not null check (month between 1 and 12),
  pdf_posted_at timestamptz not null,
  due_at timestamptz not null,
  approved_at timestamptz not null default now(),
  push_attempted_at timestamptz,
  push_sent_at timestamptz,
  push_attempts integer not null default 0,
  last_push_error text,
  unique(owner_id, year, month)
);

create index if not exists planning_auto_validation_events_pending_push_idx
  on public.planning_auto_validation_events(push_sent_at, push_attempted_at)
  where push_sent_at is null;

alter table public.planning_auto_validation_events enable row level security;
revoke all on table public.planning_auto_validation_events from public, anon, authenticated;

create or replace function public.process_due_planning_auto_validations()
returns table(
  event_id uuid,
  owner_id uuid,
  year integer,
  month integer,
  approved_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_resource record;
  v_profile record;
  v_year integer;
  v_month integer;
  v_status text;
  v_event_id uuid;
  v_approved_owner uuid;
begin
  for v_resource in
    select
      r.id,
      r.updated_at,
      r.hospital,
      r.slot,
      r.display_name
    from public.shared_resources r
    where r.kind = 'official_pdf'
      and r.updated_at <= now() - interval '7 days'
      and exists (
        select 1
        from public.official_roster_import_runs ir
        where ir.resource_id = r.id
          and ir.resource_updated_at = r.updated_at
      )
    order by r.updated_at
  loop
    v_year := null;
    v_month := null;

    -- Un PDF peut contenir quelques jours du mois précédent/suivant.
    -- On valide le mois principal : celui qui contient le plus de dates
    -- distinctes dans la lecture automatique du PDF.
    with all_dates as (
      select e.date_str as d
      from public.planning_entries e
      where e.source_resource_id = v_resource.id
        and e.source_resource_updated_at = v_resource.updated_at
        and e.deleted_at is null

      union

      select nullif(cell->>'date','')::date as d
      from public.official_roster_import_runs ir
      cross join lateral jsonb_array_elements(coalesce(ir.unmatched_cells, '[]'::jsonb)) cell
      where ir.resource_id = v_resource.id
        and ir.resource_updated_at = v_resource.updated_at
        and nullif(cell->>'date','') is not null
    ),
    month_counts as (
      select
        extract(year from d)::int as y,
        extract(month from d)::int as m,
        count(distinct d) as date_count
      from all_dates
      where d is not null
      group by 1,2
    )
    select y, m
      into v_year, v_month
    from month_counts
    order by date_count desc, y desc, m desc
    limit 1;

    if v_year is null or v_month is null then
      continue;
    end if;

    for v_profile in
      select p.id, p.prenom, p.nom
      from public.profiles p
      where p.account_status = 'active'
        and p.hospital = v_resource.hospital
      order by p.id
    loop
      v_status := null;

      select pm.status
        into v_status
      from public.planning_months pm
      where pm.owner_id = v_profile.id
        and pm.year = v_year
        and pm.month = v_month;

      if v_status = 'approved' then
        continue;
      end if;

      v_approved_owner := null;

      insert into public.planning_months(
        owner_id,
        year,
        month,
        status,
        submitted_at,
        reviewed_at,
        reviewed_by,
        rejection_reason,
        updated_at
      )
      values(
        v_profile.id,
        v_year,
        v_month,
        'approved',
        now(),
        now(),
        null,
        null,
        now()
      )
      on conflict(owner_id, year, month)
      do update
        set status = 'approved',
            submitted_at = coalesce(public.planning_months.submitted_at, now()),
            reviewed_at = now(),
            reviewed_by = null,
            rejection_reason = null,
            updated_at = now()
      where public.planning_months.status <> 'approved'
      returning owner_id into v_approved_owner;

      if v_approved_owner is null then
        continue;
      end if;

      v_event_id := null;

      insert into public.planning_auto_validation_events(
        resource_id,
        resource_updated_at,
        owner_id,
        year,
        month,
        pdf_posted_at,
        due_at,
        approved_at
      )
      values(
        v_resource.id,
        v_resource.updated_at,
        v_profile.id,
        v_year,
        v_month,
        v_resource.updated_at,
        v_resource.updated_at + interval '7 days',
        now()
      )
      on conflict(owner_id, year, month) do nothing
      returning id into v_event_id;

      if v_event_id is not null then
        perform public.write_audit(
          'planning.auto_approved',
          'planning_month',
          v_event_id::text,
          v_profile.id,
          trim(coalesce(v_profile.prenom,'') || ' ' || coalesce(v_profile.nom,'')),
          'Validation automatique 7 jours après publication du planning officiel',
          jsonb_build_object(
            'year', v_year,
            'month', v_month,
            'resource_id', v_resource.id,
            'pdf_name', v_resource.display_name,
            'pdf_posted_at', v_resource.updated_at,
            'due_at', v_resource.updated_at + interval '7 days',
            'automatic', true
          )
        );
      end if;
    end loop;
  end loop;

  return query
  select
    e.id,
    e.owner_id,
    e.year,
    e.month,
    e.approved_at
  from public.planning_auto_validation_events e
  where e.push_sent_at is null
    and (
      e.push_attempted_at is null
      or e.push_attempted_at <= now() - interval '6 hours'
    )
  order by e.approved_at
  limit 250;
end;
$$;

revoke all on function public.process_due_planning_auto_validations() from public, anon, authenticated;
grant execute on function public.process_due_planning_auto_validations() to service_role;

create or replace function public.invoke_planning_auto_validation()
returns bigint
language plpgsql
security definer
set search_path = public, extensions, net
as $$
declare
  v_key text;
  v_request_id bigint;
begin
  select sync_key::text
    into v_key
  from public.planning_auto_validation_config
  where id = true;

  if v_key is null then
    raise exception 'Planning auto-validation key is missing';
  end if;

  select net.http_post(
    url := 'https://bqmtkdzlqfvfocxlffac.supabase.co/functions/v1/auto-validate-plannings',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-planning-auto-validation-key', v_key
    ),
    body := '{}'::jsonb
  )
  into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function public.invoke_planning_auto_validation() from public, anon, authenticated;

do $cron$
declare
  v_jobid bigint;
begin
  select jobid into v_jobid
  from cron.job
  where jobname = 'gardeflow-auto-validate-plannings'
  limit 1;

  if v_jobid is not null then
    perform cron.unschedule(v_jobid);
  end if;

  perform cron.schedule(
    'gardeflow-auto-validate-plannings',
    '*/30 * * * *',
    'select public.invoke_planning_auto_validation();'
  );
end
$cron$;
