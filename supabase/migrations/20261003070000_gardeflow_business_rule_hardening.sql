-- GardeFlow hardening 2026-10-03
-- Canonical business rules, two-step planning validation, resilient QCM stats,
-- and safer automatic validation.

begin;

-- ---------------------------------------------------------------------------
-- Planning state machine metadata.
-- ---------------------------------------------------------------------------
alter table public.planning_months
  add column if not exists auto_validation_blocked boolean not null default false;

alter table public.planning_months
  add column if not exists approval_source text;

alter table public.planning_months
  drop constraint if exists planning_months_approval_source_check;

alter table public.planning_months
  add constraint planning_months_approval_source_check
  check (approval_source is null or approval_source in ('admin','automatic','legacy'));

create index if not exists planning_months_auto_validation_idx
  on public.planning_months(auto_validation_blocked,status,year,month);

create or replace function public.enforce_planning_month_state_metadata()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.status = 'submitted' then
    new.auto_validation_blocked := false;
    new.approval_source := null;
  elsif new.status = 'rejected' then
    new.auto_validation_blocked := true;
    new.approval_source := null;
  elsif tg_op = 'UPDATE'
        and old.status = 'approved'
        and new.status = 'draft' then
    -- An explicit administrative reopening must not be immediately undone by
    -- the J+7 worker when the official PDF is already older than seven days.
    new.auto_validation_blocked := true;
    new.approval_source := null;
  end if;
  return new;
end;
$$;

drop trigger if exists planning_month_state_metadata_trigger
  on public.planning_months;
create trigger planning_month_state_metadata_trigger
before insert or update of status on public.planning_months
for each row execute function public.enforce_planning_month_state_metadata();

-- ---------------------------------------------------------------------------
-- Promotion scope: only Urgences requests are restricted for the first-year
-- promotion. Pure Service requests remain governed by hospital/service rules.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_exchange_promotion_scope()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  p_from smallint;
  p_to smallint;
  p_first_year smallint;
  v_involves_emergency boolean;
begin
  select promotion_number into p_from
  from public.profiles where id = new.from_id;

  select promotion_number into p_to
  from public.profiles where id = new.to_id;

  select current_first_year_promotion into p_first_year
  from public.internship_promotion_config
  where id = 1;

  v_involves_emergency :=
    coalesce(new.shift_id,'') like 'urg-%'
    or coalesce(new.target_shift_id,'') like 'urg-%';

  if v_involves_emergency
     and p_first_year is not null
     and p_from is not null
     and p_to is not null
     and p_from <> p_to
     and (p_from = p_first_year or p_to = p_first_year) then
    raise exception
      'Pour les gardes des Urgences, la promotion de première année (Promo %) ne peut transférer ou échanger qu’avec la même promotion',
      p_first_year;
  end if;

  return new;
end;
$$;

revoke execute on function public.enforce_exchange_promotion_scope()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Doctor editing: submitted and approved months are immutable.
-- ---------------------------------------------------------------------------
create or replace function public.save_my_planning_entry(
  p_date date,
  p_shift_id text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  me public.profiles%rowtype;
  month_state text;
  existing public.planning_entries%rowtype;
  entry_id text;
  y int := extract(year from p_date)::int;
  m int := extract(month from p_date)::int;
  max_date date := make_date(extract(year from current_date)::int + 2, 12, 31);
begin
  select * into me
  from public.profiles
  where id=(select auth.uid()) and account_status='active';

  if not found then raise exception 'Compte actif requis'; end if;
  if p_date < current_date then
    raise exception 'Une date passée ne peut plus être modifiée';
  end if;

  if p_shift_id not in (
    'service-jour','service-24h','service-nuit',
    'urg-jour','urg-24h','urg-nuit','conge'
  ) then
    raise exception 'Type de tuile invalide';
  end if;

  if p_date > max_date then
    raise exception 'Cette date dépasse l’horizon de planification autorisé';
  end if;

  if p_shift_id <> 'conge'
     and public.guard_has_started(p_date, p_shift_id) then
    raise exception 'Cette garde a déjà commencé et ne peut plus être ajoutée ou modifiée';
  end if;

  select status into month_state
  from public.planning_months
  where owner_id=me.id and year=y and month=m
  for update;

  if month_state='submitted' then
    raise exception 'Calendrier soumis : il est figé en attente de validation finale';
  elsif month_state='approved' then
    raise exception 'Calendrier validé définitivement : aucune modification directe n’est possible';
  end if;

  insert into public.planning_months(owner_id,year,month,status,updated_at)
  values(me.id,y,m,'draft',now())
  on conflict(owner_id,year,month) do update
    set status='draft',
        submitted_at=null,
        reviewed_at=null,
        reviewed_by=null,
        rejection_reason=null,
        updated_at=now()
    where public.planning_months.status in ('draft','rejected');

  select * into existing
  from public.planning_entries
  where owner_id=me.id and date_str=p_date and deleted_at is null
  for update;

  if found then
    if existing.shift_id='conge'
       and existing.leave_request_id is not null
       and exists(
         select 1 from public.leave_requests l
         where l.id=existing.leave_request_id and l.status='approved'
       ) then
      raise exception 'Ce congé a déjà été approuvé : seul un administrateur peut le supprimer';
    end if;

    if exists(
      select 1 from public.exchange_requests r
      where r.status in ('pendingB','pendingAdmin')
        and (r.planning_entry_id=existing.id or r.target_planning_entry_id=existing.id)
    ) then
      raise exception 'Cette garde est verrouillée par une demande active';
    end if;

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
      entry_id,p_date,p_shift_id,me.id,me.phone,
      trim(me.prenom||' '||me.nom),now()
    );
  end if;

  return entry_id;
end;
$$;

revoke execute on function public.save_my_planning_entry(date,text)
  from public, anon;
grant execute on function public.save_my_planning_entry(date,text)
  to authenticated;

create or replace function public.delete_my_planning_entry(p_entry_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me public.profiles%rowtype;
  e public.planning_entries%rowtype;
  month_state text;
  y int;
  m int;
begin
  select * into me
  from public.profiles
  where id=(select auth.uid()) and account_status='active';
  if not found then raise exception 'Compte actif requis'; end if;

  select * into e
  from public.planning_entries
  where id=p_entry_id and owner_id=me.id and deleted_at is null
  for update;
  if not found then raise exception 'Affectation introuvable'; end if;

  if e.date_str < current_date then
    raise exception 'Une date passée ne peut plus être modifiée';
  end if;
  if e.shift_id <> 'conge'
     and public.guard_has_started(e.date_str,e.shift_id) then
    raise exception 'Cette garde a déjà commencé et ne peut plus être supprimée';
  end if;

  y:=extract(year from e.date_str)::int;
  m:=extract(month from e.date_str)::int;
  select status into month_state
  from public.planning_months
  where owner_id=me.id and year=y and month=m
  for update;

  if month_state='submitted' then
    raise exception 'Calendrier soumis : il est figé en attente de validation finale';
  elsif month_state='approved' then
    raise exception 'Calendrier validé définitivement : seul un administrateur peut supprimer une garde validée';
  end if;

  if e.shift_id='conge'
     and e.leave_request_id is not null
     and exists(
       select 1 from public.leave_requests l
       where l.id=e.leave_request_id and l.status='approved'
     ) then
    raise exception 'Ce congé a déjà été approuvé : seul un administrateur peut le supprimer';
  end if;

  if exists(
    select 1 from public.exchange_requests r
    where r.status in ('pendingB','pendingAdmin')
      and (r.planning_entry_id=e.id or r.target_planning_entry_id=e.id)
  ) then
    raise exception 'Cette garde est verrouillée par une demande active';
  end if;

  update public.planning_entries set deleted_at=now() where id=e.id;

  insert into public.planning_months(owner_id,year,month,status,updated_at)
  values(me.id,y,m,'draft',now())
  on conflict(owner_id,year,month) do update
    set status='draft',
        submitted_at=null,
        reviewed_at=null,
        reviewed_by=null,
        rejection_reason=null,
        updated_at=now()
    where public.planning_months.status in ('draft','rejected');
end;
$$;

revoke execute on function public.delete_my_planning_entry(text)
  from public, anon;
grant execute on function public.delete_my_planning_entry(text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Personal submission now creates the submitted state, not final approval.
-- ---------------------------------------------------------------------------
create or replace function public.submit_my_planning_month(
  p_year integer,
  p_month integer
)
returns text[]
language plpgsql
security definer
set search_path = ''
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
  select * into me
  from public.profiles
  where id=(select auth.uid()) and account_status='active';
  if not found then raise exception 'Compte actif requis'; end if;

  if p_year not between 2020 and 2100 or p_month not between 1 and 12 then
    raise exception 'Mois invalide';
  end if;

  first_day:=make_date(p_year,p_month,1);
  last_day:=(first_day + interval '1 month - 1 day')::date;
  if first_day < date_trunc('month',current_date)::date then
    raise exception 'Un mois passé ne peut plus être soumis';
  end if;

  select status into current_state
  from public.planning_months
  where owner_id=me.id and year=p_year and month=p_month
  for update;

  if current_state='submitted' then
    raise exception 'Calendrier déjà soumis et en attente de validation finale';
  elsif current_state='approved' then
    raise exception 'Calendrier déjà validé définitivement';
  end if;

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
      jsonb_build_object(
        'start_date',range_rec.start_date,
        'end_date',range_rec.end_date,
        'source','planning_tile'
      )
    );
  end loop;

  insert into public.planning_months(
    owner_id,year,month,status,submitted_at,reviewed_at,reviewed_by,
    rejection_reason,updated_at,auto_validation_blocked,approval_source
  ) values (
    me.id,p_year,p_month,'submitted',now(),null,null,null,now(),false,null
  )
  on conflict(owner_id,year,month) do update
    set status='submitted',
        submitted_at=now(),
        reviewed_at=null,
        reviewed_by=null,
        rejection_reason=null,
        updated_at=now(),
        auto_validation_blocked=false,
        approval_source=null
    where public.planning_months.status in ('draft','rejected');

  perform public.write_audit(
    'planning_month.submitted','planning_month',
    me.id::text||':'||p_year||':'||p_month,
    me.id,trim(me.prenom||' '||me.nom),null,
    jsonb_build_object(
      'year',p_year,
      'month',p_month,
      'awaiting_final_approval',true,
      'auto_validation_fallback',true
    )
  );

  return created_leave_ids;
end;
$$;

revoke execute on function public.submit_my_planning_month(integer,integer)
  from public, anon;
grant execute on function public.submit_my_planning_month(integer,integer)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Explicit admin final approval/rejection.
-- ---------------------------------------------------------------------------
create or replace function public.review_planning_month(
  p_owner_id uuid,
  p_year integer,
  p_month integer,
  p_action text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_profile public.profiles%rowtype;
  month_state text;
  first_day date;
  last_day date;
  pending_leave_ids text[] := array[]::text[];
  clean_reason text := trim(coalesce(p_reason,''));
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;
  if p_owner_id=(select auth.uid()) then
    raise exception 'Un administrateur ne peut pas valider ou rejeter son propre calendrier';
  end if;
  if p_year not between 2020 and 2100 or p_month not between 1 and 12 then
    raise exception 'Mois invalide';
  end if;
  if p_action not in ('approve','reject') then
    raise exception 'Action invalide';
  end if;
  if p_action='reject' and length(clean_reason)<3 then
    raise exception 'Motif de rejet obligatoire';
  end if;

  first_day:=make_date(p_year,p_month,1);
  last_day:=(first_day + interval '1 month - 1 day')::date;
  if first_day < date_trunc('month',current_date)::date then
    raise exception 'Un mois passé est en lecture seule';
  end if;

  select * into target_profile
  from public.profiles
  where id=p_owner_id and account_status='active';
  if not found then raise exception 'Médecin introuvable ou inactif'; end if;

  select status into month_state
  from public.planning_months
  where owner_id=p_owner_id and year=p_year and month=p_month
  for update;
  if not found or month_state<>'submitted' then
    raise exception 'Ce calendrier n’est plus en attente de validation';
  end if;

  if p_action='approve' then
    update public.planning_months
       set status='approved',
           reviewed_at=now(),
           reviewed_by=(select auth.uid()),
           rejection_reason=null,
           updated_at=now(),
           auto_validation_blocked=false,
           approval_source='admin'
     where owner_id=p_owner_id and year=p_year and month=p_month;

    perform public.write_audit(
      'planning_month.approved','planning_month',
      p_owner_id::text||':'||p_year||':'||p_month,
      p_owner_id,trim(target_profile.prenom||' '||target_profile.nom),null,
      jsonb_build_object('year',p_year,'month',p_month,'source','admin')
    );
    return;
  end if;

  -- A rejected submission becomes editable again. Pending leave requests that
  -- were created by that submission are cancelled and will be recreated after
  -- the doctor corrects/resubmits the month. Approved leaves remain untouched.
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

  if coalesce(cardinality(pending_leave_ids),0)>0 then
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
     set status='rejected',
         reviewed_at=now(),
         reviewed_by=(select auth.uid()),
         rejection_reason=clean_reason,
         updated_at=now(),
         auto_validation_blocked=true,
         approval_source=null
   where owner_id=p_owner_id and year=p_year and month=p_month;

  perform public.write_audit(
    'planning_month.rejected','planning_month',
    p_owner_id::text||':'||p_year||':'||p_month,
    p_owner_id,trim(target_profile.prenom||' '||target_profile.nom),clean_reason,
    jsonb_build_object('year',p_year,'month',p_month,'source','admin')
  );
end;
$$;

revoke execute on function public.review_planning_month(uuid,integer,integer,text,text)
  from public, anon;
grant execute on function public.review_planning_month(uuid,integer,integer,text,text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Auto-validation respects explicit admin correction/reopening holds.
-- ---------------------------------------------------------------------------
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
set search_path = ''
as $$
declare
  v_resource record;
  v_profile record;
  v_year integer;
  v_month integer;
  v_status text;
  v_blocked boolean;
  v_event_id uuid;
  v_approved_owner uuid;
begin
  for v_resource in
    select
      r.id,
      r.updated_at,
      case r.slot
        when 'hm6_bouskoura' then 'Hôpital Universitaire International Mohammed VI de Bouskoura'
        when 'hm6_rabat' then 'Hôpital Universitaire International Mohammed VI de Rabat'
        when 'hck_casa' then 'Hôpital Universitaire International Cheikh Khalifa de Casablanca'
        else r.hospital
      end as hospital,
      r.slot,
      r.display_name
    from public.shared_resources r
    where r.kind='official_pdf'
      and r.updated_at <= now() - interval '7 days'
      and exists (
        select 1 from public.official_roster_import_runs ir
        where ir.resource_id=r.id
          and ir.resource_updated_at=r.updated_at
      )
    order by r.updated_at
  loop
    v_year:=null;
    v_month:=null;

    with all_dates as (
      select e.date_str as d
      from public.planning_entries e
      where e.source_resource_id=v_resource.id
        and e.source_resource_updated_at=v_resource.updated_at
        and e.deleted_at is null
      union
      select nullif(cell->>'date','')::date as d
      from public.official_roster_import_runs ir
      cross join lateral jsonb_array_elements(coalesce(ir.unmatched_cells,'[]'::jsonb)) cell
      where ir.resource_id=v_resource.id
        and ir.resource_updated_at=v_resource.updated_at
        and nullif(cell->>'date','') is not null
    ), month_counts as (
      select extract(year from d)::int as y,
             extract(month from d)::int as m,
             count(distinct d) as date_count
      from all_dates where d is not null
      group by 1,2
    )
    select y,m into v_year,v_month
    from month_counts
    order by date_count desc,y desc,m desc
    limit 1;

    if v_year is null or v_month is null then continue; end if;

    for v_profile in
      select p.id,p.prenom,p.nom
      from public.profiles p
      where p.account_status='active'
        and p.hospital=v_resource.hospital
      order by p.id
    loop
      v_status:=null;
      v_blocked:=false;
      select pm.status,pm.auto_validation_blocked
        into v_status,v_blocked
      from public.planning_months pm
      where pm.owner_id=v_profile.id
        and pm.year=v_year
        and pm.month=v_month;

      if v_status='approved'
         or v_status='rejected'
         or coalesce(v_blocked,false) then
        continue;
      end if;

      v_approved_owner:=null;
      insert into public.planning_months(
        owner_id,year,month,status,submitted_at,reviewed_at,reviewed_by,
        rejection_reason,updated_at,auto_validation_blocked,approval_source
      ) values (
        v_profile.id,v_year,v_month,'approved',now(),now(),null,
        null,now(),false,'automatic'
      )
      on conflict(owner_id,year,month) do update
        set status='approved',
            submitted_at=coalesce(public.planning_months.submitted_at,now()),
            reviewed_at=now(),
            reviewed_by=null,
            rejection_reason=null,
            updated_at=now(),
            auto_validation_blocked=false,
            approval_source='automatic'
        where public.planning_months.status in ('draft','submitted')
          and not public.planning_months.auto_validation_blocked
      returning owner_id into v_approved_owner;

      if v_approved_owner is null then continue; end if;

      v_event_id:=null;
      insert into public.planning_auto_validation_events(
        resource_id,resource_updated_at,owner_id,year,month,
        pdf_posted_at,due_at,approved_at
      ) values (
        v_resource.id,v_resource.updated_at,v_profile.id,v_year,v_month,
        v_resource.updated_at,v_resource.updated_at + interval '7 days',now()
      )
      on conflict(owner_id,year,month) do nothing
      returning id into v_event_id;

      if v_event_id is not null then
        perform public.write_audit(
          'planning.auto_approved','planning_month',v_event_id::text,
          v_profile.id,
          trim(coalesce(v_profile.prenom,'')||' '||coalesce(v_profile.nom,'')),
          'Validation automatique 7 jours après publication du planning officiel',
          jsonb_build_object(
            'year',v_year,
            'month',v_month,
            'resource_id',v_resource.id,
            'pdf_name',v_resource.display_name,
            'pdf_posted_at',v_resource.updated_at,
            'due_at',v_resource.updated_at + interval '7 days',
            'automatic',true
          )
        );
      end if;
    end loop;
  end loop;

  return query
  select e.id,e.owner_id,e.year,e.month,e.approved_at
  from public.planning_auto_validation_events e
  where e.push_sent_at is null
    and (e.push_attempted_at is null
         or e.push_attempted_at <= now() - interval '6 hours')
  order by e.approved_at
  limit 250;
end;
$$;

revoke execute on function public.process_due_planning_auto_validations()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- QCM: immutable response-event ledger. The existing answer_history remains
-- the canonical first-answer snapshot for per-QCM state; statistics use the
-- event ledger so historical identity-attribution repairs are auditable.
-- ---------------------------------------------------------------------------
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.clinical_case_qcm_response_events (
  event_id uuid primary key,
  actor_user_id uuid not null references public.profiles(id) on delete cascade,
  stats_user_id uuid not null references public.profiles(id) on delete cascade,
  qcm_id uuid not null references public.clinical_case_qcms(id) on delete cascade,
  post_id uuid not null references public.clinical_case_posts(id) on delete cascade,
  selected_index smallint not null check (selected_index between 0 and 3),
  is_correct boolean not null,
  answered_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  source text not null default 'answer_insert',
  attribution_reason text
);

create index if not exists qcm_response_events_stats_time_idx
  on private.clinical_case_qcm_response_events(stats_user_id,answered_at);
create index if not exists qcm_response_events_actor_time_idx
  on private.clinical_case_qcm_response_events(actor_user_id,answered_at);
create index if not exists qcm_response_events_stats_qcm_idx
  on private.clinical_case_qcm_response_events(stats_user_id,qcm_id);

insert into private.clinical_case_qcm_response_events(
  event_id,actor_user_id,stats_user_id,qcm_id,post_id,selected_index,
  is_correct,answered_at,recorded_at,source
)
select
  h.answer_id,h.user_id,h.user_id,h.qcm_id,h.post_id,h.selected_index,
  h.is_correct,h.answered_at,coalesce(h.recorded_at,h.answered_at),'history_backfill'
from public.clinical_case_qcm_answer_history h
on conflict(event_id) do nothing;

create or replace function private.record_clinical_case_qcm_response_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post uuid;
begin
  select q.post_id into v_post
  from public.clinical_case_qcms q
  where q.id=new.qcm_id;

  if v_post is null then
    raise exception 'QCM sans cas clinique associé';
  end if;

  insert into private.clinical_case_qcm_response_events(
    event_id,actor_user_id,stats_user_id,qcm_id,post_id,selected_index,
    is_correct,answered_at,source
  ) values (
    new.id,new.user_id,new.user_id,new.qcm_id,v_post,new.selected_index,
    new.is_correct,new.answered_at,'answer_insert'
  )
  on conflict(event_id) do nothing;

  return new;
end;
$$;

revoke execute on function private.record_clinical_case_qcm_response_event()
  from public, anon, authenticated;

drop trigger if exists clinical_case_record_qcm_response_event
  on public.clinical_case_qcm_answers;
create trigger clinical_case_record_qcm_response_event
after insert on public.clinical_case_qcm_answers
for each row execute function private.record_clinical_case_qcm_response_event();

create or replace function public.clinical_case_qcm_stats()
returns table(
  total_answered bigint,total_correct bigint,total_accuracy numeric,
  month_answered bigint,month_correct bigint,month_accuracy numeric,
  year_answered bigint,year_correct bigint,year_accuracy numeric,xp bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid:=(select auth.uid());
  v_month timestamptz:=date_trunc('month',now() at time zone 'Africa/Casablanca') at time zone 'Africa/Casablanca';
  v_year timestamptz:=date_trunc('year',now() at time zone 'Africa/Casablanca') at time zone 'Africa/Casablanca';
begin
  if v_uid is null then raise exception 'Authentification requise.'; end if;
  return query with s as (
    select count(*)::bigint n,
      count(*) filter(where h.is_correct)::bigint ok,
      count(*) filter(where h.answered_at>=v_month)::bigint mn,
      count(*) filter(where h.answered_at>=v_month and h.is_correct)::bigint mnok,
      count(*) filter(where h.answered_at>=v_year)::bigint yr,
      count(*) filter(where h.answered_at>=v_year and h.is_correct)::bigint yrok
    from private.clinical_case_qcm_response_events h
    where h.stats_user_id=v_uid
  )
  select n,ok,
    case when n=0 then 0 else round(100.0*ok/n,1) end,
    mn,mnok,case when mn=0 then 0 else round(100.0*mnok/mn,1) end,
    yr,yrok,case when yr=0 then 0 else round(100.0*yrok/yr,1) end,
    (n*2+ok*3)::bigint
  from s;
end;
$$;

revoke execute on function public.clinical_case_qcm_stats() from public, anon;
grant execute on function public.clinical_case_qcm_stats() to authenticated;

create or replace function public.clinical_case_qcm_summary(p_period text default 'month')
returns table(answered bigint,correct bigint,accuracy numeric)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid:=(select auth.uid());
  v_start timestamptz;
  v_end timestamptz;
begin
  if v_uid is null then raise exception 'Authentification requise.'; end if;
  if p_period not in('month','year','all') then raise exception 'Période QCM invalide.'; end if;
  if p_period='month' then
    v_start:=date_trunc('month',now() at time zone 'Africa/Casablanca') at time zone 'Africa/Casablanca';
    v_end:=(date_trunc('month',now() at time zone 'Africa/Casablanca')+interval '1 month') at time zone 'Africa/Casablanca';
  elsif p_period='year' then
    v_start:=date_trunc('year',now() at time zone 'Africa/Casablanca') at time zone 'Africa/Casablanca';
    v_end:=(date_trunc('year',now() at time zone 'Africa/Casablanca')+interval '1 year') at time zone 'Africa/Casablanca';
  else
    v_start:='-infinity'::timestamptz;
    v_end:='infinity'::timestamptz;
  end if;

  return query
  select count(*)::bigint,
         count(*) filter(where a.is_correct)::bigint,
         case when count(*)=0 then 0::numeric
              else round(100.0*count(*) filter(where a.is_correct)/count(*),1)
         end
  from private.clinical_case_qcm_response_events a
  where a.stats_user_id=v_uid
    and a.answered_at>=v_start and a.answered_at<v_end;
end;
$$;

revoke execute on function public.clinical_case_qcm_summary(text) from public, anon;
grant execute on function public.clinical_case_qcm_summary(text) to authenticated;

create or replace function public.clinical_case_qcm_leaderboard(
  p_period text default 'month',
  p_promotion smallint default null
)
returns table(
  rank bigint,user_id uuid,display_name text,promotion_number smallint,
  correct bigint,answered bigint,accuracy numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_start timestamptz;
  v_end timestamptz;
begin
  if (select auth.uid()) is null then raise exception 'Authentification requise.'; end if;
  if p_period not in('month','year') then raise exception 'Période QCM invalide.'; end if;

  if p_period='month' then
    v_start:=date_trunc('month',now() at time zone 'Africa/Casablanca') at time zone 'Africa/Casablanca';
    v_end:=(date_trunc('month',now() at time zone 'Africa/Casablanca')+interval '1 month') at time zone 'Africa/Casablanca';
  else
    v_start:=date_trunc('year',now() at time zone 'Africa/Casablanca') at time zone 'Africa/Casablanca';
    v_end:=(date_trunc('year',now() at time zone 'Africa/Casablanca')+interval '1 year') at time zone 'Africa/Casablanca';
  end if;

  return query with scores as(
    select p.id uid,
      trim(concat_ws(' ','Dr',nullif(p.prenom,''),nullif(p.nom,''))) display_name,
      p.promotion_number,
      count(*) filter(where a.is_correct)::bigint correct_count,
      count(*)::bigint answered_count,
      round(100.0*count(*) filter(where a.is_correct)/nullif(count(*),0),1) accuracy_pct
    from public.profiles p
    join private.clinical_case_qcm_response_events a on a.stats_user_id=p.id
    left join public.practice_preferences pref on pref.user_id=p.id
    where a.answered_at>=v_start and a.answered_at<v_end
      and coalesce(pref.leaderboard_opt_in,true)
      and coalesce(p.account_status,'active')='active'
      and coalesce(p.medical_grade,'junior')='junior'
      and (p_promotion is null or p.promotion_number=p_promotion)
    group by p.id,p.prenom,p.nom,p.promotion_number
  ), ranked as(
    select dense_rank() over(
      order by s.correct_count desc,s.accuracy_pct desc,s.answered_count desc,s.uid
    )::bigint rnk,s.* from scores s
  )
  select r.rnk,r.uid,r.display_name,r.promotion_number,
         r.correct_count,r.answered_count,r.accuracy_pct
  from ranked r order by r.rnk,r.display_name;
end;
$$;

revoke execute on function public.clinical_case_qcm_leaderboard(text,smallint)
  from public, anon;
grant execute on function public.clinical_case_qcm_leaderboard(text,smallint)
  to authenticated;

create or replace function public.practice_refresh_my_achievements()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid:=(select auth.uid());
  a record;
  progress_value integer;
  total_patients integer;
  total_complete integer;
  total_specialist integer;
  total_guards integer;
  current_streak integer;
  qcm_answered integer;
  qcm_correct integer;
  clinical_xp integer;
  combined_xp integer;
begin
  if uid is null then raise exception 'Authentification requise.'; end if;

  select count(*)::int,
    count(*) filter(where public.practice_case_is_complete(pc))::int,
    count(*) filter(where pc.specialist_opinion_requested)::int,
    count(distinct pc.guard_id)::int,
    coalesce(sum(public.practice_case_xp(pc)),0)::int
  into total_patients,total_complete,total_specialist,total_guards,clinical_xp
  from public.practice_cases pc
  where pc.user_id=uid and pc.is_draft=false and public.practice_case_is_valid(pc);

  select count(*)::int,count(*) filter(where qa.is_correct)::int
  into qcm_answered,qcm_correct
  from private.clinical_case_qcm_response_events qa
  where qa.stats_user_id=uid;

  current_streak:=public.practice_current_streak(uid);
  combined_xp:=clinical_xp+qcm_answered*2+qcm_correct*3;

  for a in select * from public.practice_achievements loop
    progress_value:=case a.metric
      when 'patients' then total_patients
      when 'complete' then total_complete
      when 'specialist' then total_specialist
      when 'guards' then total_guards
      when 'streak' then current_streak
      when 'qcm_answered' then qcm_answered
      when 'qcm_correct' then qcm_correct
      when 'xp' then combined_xp
      else 0
    end;
    insert into public.user_practice_achievements(
      user_id,achievement_id,progress,unlocked_at,updated_at
    ) values (
      uid,a.id,progress_value,
      case when progress_value>=a.threshold then now() else null end,now()
    )
    on conflict(user_id,achievement_id) do update set
      progress=excluded.progress,
      unlocked_at=coalesce(public.user_practice_achievements.unlocked_at,excluded.unlocked_at),
      updated_at=now();
  end loop;
end;
$$;

revoke execute on function public.practice_refresh_my_achievements()
  from public, anon;
grant execute on function public.practice_refresh_my_achievements()
  to authenticated;

commit;
