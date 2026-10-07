-- GardeFlow R6 — functional lock for official rosters.
-- Additive migration only: R4/R5 protections remain authoritative.

create or replace function public.guardeflow_normalize_official_identity(p_value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select trim(
    regexp_replace(
      replace(
        replace(
          replace(
            replace(
              replace(
                replace(
                  replace(
                    translate(
                      lower(coalesce(p_value,'')),
                      'àáâäãåçèéêëìíîïñòóôöõùúûüýÿ',
                      'aaaaaaceeeeiiiinooooouuuuyy'
                    ),
                    'æ','ae'
                  ),
                  'œ','oe'
                ),
                '’',' '
              ),
              '''',' '
            ),
            '-',' '
          ),
          '–',' '
        ),
        '—',' '
      ),
      '\s+',
      ' ',
      'g'
    )
  );
$$;

create table if not exists public.official_roster_import_reports (
  id uuid primary key default gen_random_uuid(),
  resource_id uuid not null references public.shared_resources(id) on delete cascade,
  resource_updated_at timestamptz not null,
  slot text not null,
  hospital text not null,
  file_name text not null,
  imported_by uuid references public.profiles(id) on delete set null,
  parser_revision text not null,
  engine text not null,
  status text not null check (status in ('green','orange','red')),
  confidence numeric(6,5) not null check (confidence >= 0 and confidence <= 1),
  page_count integer not null default 0 check (page_count >= 0),
  covered_days integer not null default 0 check (covered_days >= 0),
  total_guards integer not null default 0 check (total_guards >= 0),
  doctor_count integer not null default 0 check (doctor_count >= 0),
  registered_doctors integer not null default 0 check (registered_doctors >= 0),
  unregistered_doctors integer not null default 0 check (unregistered_doctors >= 0),
  ambiguous_matches integer not null default 0 check (ambiguous_matches >= 0),
  manual_review_matches integer not null default 0 check (manual_review_matches >= 0),
  ab_difference_count integer not null default 0 check (ab_difference_count >= 0),
  c_intervention_count integer not null default 0 check (c_intervention_count >= 0),
  low_confidence_count integer not null default 0 check (low_confidence_count >= 0),
  uninterpreted_zone_count integer not null default 0 check (uninterpreted_zone_count >= 0),
  anomaly_count integer not null default 0 check (anomaly_count >= 0),
  manual_correction_count integer not null default 0 check (manual_correction_count >= 0),
  unmatched_cells jsonb not null default '[]'::jsonb,
  report_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(resource_id, resource_updated_at, parser_revision)
);

create table if not exists public.official_roster_guards (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.official_roster_import_reports(id) on delete cascade,
  resource_id uuid not null references public.shared_resources(id) on delete cascade,
  resource_updated_at timestamptz not null,
  parser_revision text not null,
  source_ordinal integer not null check (source_ordinal > 0),
  slot text not null,
  hospital text not null,
  date_str date not null,
  shift_id text not null check (shift_id in ('urg-jour','urg-nuit','urg-24h')),
  duty_area text not null default 'urgences',
  first_name text not null,
  last_name text not null,
  full_name text not null,
  normalized_first_name text not null,
  normalized_last_name text not null,
  page_number integer check (page_number is null or page_number > 0),
  zone text,
  confidence numeric(6,5) not null check (confidence >= 0 and confidence <= 1),
  review_status text not null check (review_status in ('green','orange','red')),
  is_disciplinary boolean not null default false,
  match_status text not null check (
    match_status in ('matched','unregistered','ambiguous','manual_review')
  ),
  matched_profile_id uuid references public.profiles(id) on delete set null,
  source_details jsonb not null default '{}'::jsonb,
  correction_history jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(
    resource_id,
    resource_updated_at,
    parser_revision,
    date_str,
    shift_id,
    source_ordinal
  )
);

create index if not exists official_roster_guards_current_profile_idx
  on public.official_roster_guards(
    resource_id,
    resource_updated_at,
    matched_profile_id,
    date_str
  );

create index if not exists official_roster_guards_identity_idx
  on public.official_roster_guards(
    hospital,
    normalized_first_name,
    normalized_last_name
  );

create index if not exists official_roster_guards_review_idx
  on public.official_roster_guards(review_status, match_status, confidence);

create table if not exists public.official_roster_identity_links (
  id uuid primary key default gen_random_uuid(),
  hospital text not null,
  official_first_name text not null,
  official_last_name text not null,
  official_full_name text not null,
  normalized_first_name text not null,
  normalized_last_name text not null,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  reason text
);

create unique index if not exists official_roster_identity_links_active_uidx
  on public.official_roster_identity_links(
    hospital,
    normalized_first_name,
    normalized_last_name
  )
  where active;

create index if not exists official_roster_identity_links_profile_idx
  on public.official_roster_identity_links(profile_id)
  where active;

create table if not exists public.official_roster_anomalies (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.official_roster_import_reports(id) on delete cascade,
  resource_id uuid not null references public.shared_resources(id) on delete cascade,
  resource_updated_at timestamptz not null,
  parser_revision text not null,
  anomaly_code text not null,
  date_str date,
  shift_id text check (
    shift_id is null or shift_id in ('urg-jour','urg-nuit','urg-24h')
  ),
  page_number integer check (page_number is null or page_number > 0),
  zone text,
  message text not null,
  read_a jsonb not null default '{}'::jsonb,
  read_b jsonb not null default '{}'::jsonb,
  read_c jsonb,
  status text not null default 'pending'
    check (status in ('pending','resolved_auto','resolved_manual','dismissed')),
  resolution jsonb,
  resolved_by uuid references public.profiles(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists official_roster_anomalies_report_idx
  on public.official_roster_anomalies(report_id, status, date_str);

create table if not exists public.official_roster_recalculation_runs (
  id uuid primary key default gen_random_uuid(),
  scope text not null check (scope in ('individual','global')),
  profile_id uuid references public.profiles(id) on delete set null,
  resource_id uuid references public.shared_resources(id) on delete set null,
  resource_updated_at timestamptz,
  requested_by uuid references public.profiles(id) on delete set null,
  preview jsonb not null default '{}'::jsonb,
  preview_token text not null,
  applied boolean not null default false,
  result jsonb,
  error text,
  created_at timestamptz not null default now(),
  applied_at timestamptz
);

create index if not exists official_roster_recalc_profile_idx
  on public.official_roster_recalculation_runs(profile_id, created_at desc);

alter table public.official_roster_import_reports enable row level security;
alter table public.official_roster_guards enable row level security;
alter table public.official_roster_identity_links enable row level security;
alter table public.official_roster_anomalies enable row level security;
alter table public.official_roster_recalculation_runs enable row level security;

drop policy if exists "admins manage official roster reports"
  on public.official_roster_import_reports;
create policy "admins manage official roster reports"
  on public.official_roster_import_reports
  for all
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "admins manage official roster guards"
  on public.official_roster_guards;
create policy "admins manage official roster guards"
  on public.official_roster_guards
  for all
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "admins manage official roster identity links"
  on public.official_roster_identity_links;
create policy "admins manage official roster identity links"
  on public.official_roster_identity_links
  for all
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "admins manage official roster anomalies"
  on public.official_roster_anomalies;
create policy "admins manage official roster anomalies"
  on public.official_roster_anomalies
  for all
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "admins manage official roster recalculations"
  on public.official_roster_recalculation_runs;
create policy "admins manage official roster recalculations"
  on public.official_roster_recalculation_runs
  for all
  using (public.is_admin())
  with check (public.is_admin());

create or replace function public.save_official_roster_analysis_r6(
  p_resource_id uuid,
  p_resource_updated_at timestamptz,
  p_extraction jsonb,
  p_guards jsonb,
  p_unmatched_cells jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource public.shared_resources%rowtype;
  v_report_id uuid;
  v_item jsonb;
  v_status text;
  v_engine text;
  v_revision text;
  v_confidence numeric;
  v_ordinal integer := 0;
  v_date date;
  v_shift text;
  v_first text;
  v_last text;
  v_full text;
  v_norm_first text;
  v_norm_last text;
  v_match_status text;
  v_profile_id uuid;
  v_link_profile_id uuid;
  v_page integer;
  v_zone text;
  v_guard_confidence numeric;
  v_review_status text;
  v_is_disciplinary boolean;
  v_actor_name text;
  v_conflict jsonb;
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;

  select *
  into v_resource
  from public.shared_resources
  where id = p_resource_id
    and kind = 'official_pdf'
    and updated_at = p_resource_updated_at
  for update;

  if not found then
    raise exception 'Planning officiel introuvable ou remplacé';
  end if;

  v_revision := coalesce(nullif(p_extraction->>'parser_revision',''), 'v12.0.2-r6');
  if public.guardeflow_roster_revision_rank(v_revision) < 6 then
    raise exception 'Analyse R6 requise';
  end if;

  v_status := lower(coalesce(p_extraction->>'status','red'));
  if coalesce((p_extraction->>'verified')::boolean,false) is not true
     or v_status not in ('green','orange') then
    raise exception 'Analyse non publiable : statut %', v_status;
  end if;

  v_engine := coalesce(
    nullif(p_extraction->>'engine',''),
    'pdfrx_geometry+openai_visual_conditional'
  );
  v_confidence := greatest(
    0,
    least(1, coalesce(nullif(p_extraction->>'confidence','')::numeric,0))
  );
  if v_confidence < 0.90 then
    raise exception 'Confiance globale insuffisante';
  end if;

  if jsonb_typeof(coalesce(p_guards,'[]'::jsonb)) <> 'array' then
    raise exception 'Liste des gardes invalide';
  end if;

  insert into public.official_roster_import_reports(
    resource_id,
    resource_updated_at,
    slot,
    hospital,
    file_name,
    imported_by,
    parser_revision,
    engine,
    status,
    confidence,
    page_count,
    covered_days,
    total_guards,
    doctor_count,
    registered_doctors,
    unregistered_doctors,
    ambiguous_matches,
    manual_review_matches,
    ab_difference_count,
    c_intervention_count,
    low_confidence_count,
    uninterpreted_zone_count,
    anomaly_count,
    manual_correction_count,
    unmatched_cells,
    report_payload,
    updated_at
  ) values (
    v_resource.id,
    v_resource.updated_at,
    coalesce(v_resource.slot,''),
    coalesce(v_resource.hospital,''),
    v_resource.display_name,
    auth.uid(),
    v_revision,
    v_engine,
    v_status,
    v_confidence,
    coalesce((
      select max(nullif(value->>'page_number','')::int)
      from jsonb_array_elements(coalesce(p_extraction->'rows','[]'::jsonb))
      where value ? 'page_number'
        and (value->>'page_number') ~ '^[0-9]+$'
    ),0),
    coalesce((
      select count(distinct value->>'date')::int
      from jsonb_array_elements(coalesce(p_extraction->'rows','[]'::jsonb))
      where value ? 'date'
    ),0),
    jsonb_array_length(coalesce(p_guards,'[]'::jsonb)),
    0,0,0,0,0,
    jsonb_array_length(coalesce(p_extraction->'conflicts','[]'::jsonb)),
    case
      when coalesce((p_extraction->'read_summary'->>'c_executed')::boolean,false)
      then 1 else 0
    end,
    0,
    jsonb_array_length(coalesce(p_extraction->'validation_errors','[]'::jsonb)),
    jsonb_array_length(coalesce(p_extraction->'conflicts','[]'::jsonb)),
    0,
    case
      when jsonb_typeof(coalesce(p_unmatched_cells,'[]'::jsonb))='array'
      then coalesce(p_unmatched_cells,'[]'::jsonb)
      else '[]'::jsonb
    end,
    p_extraction,
    now()
  )
  on conflict(resource_id, resource_updated_at, parser_revision)
  do update set
    imported_by = excluded.imported_by,
    engine = excluded.engine,
    status = excluded.status,
    confidence = excluded.confidence,
    page_count = excluded.page_count,
    covered_days = excluded.covered_days,
    total_guards = excluded.total_guards,
    ab_difference_count = excluded.ab_difference_count,
    c_intervention_count = excluded.c_intervention_count,
    uninterpreted_zone_count = excluded.uninterpreted_zone_count,
    anomaly_count = excluded.anomaly_count,
    unmatched_cells = excluded.unmatched_cells,
    report_payload = excluded.report_payload,
    updated_at = now()
  returning id into v_report_id;

  delete from public.official_roster_anomalies
  where report_id = v_report_id;

  delete from public.official_roster_guards
  where report_id = v_report_id;

  for v_item in
    select value
    from jsonb_array_elements(coalesce(p_guards,'[]'::jsonb))
  loop
    v_ordinal := v_ordinal + 1;

    begin
      v_date := nullif(v_item->>'date','')::date;
    exception when others then
      raise exception 'Date de garde invalide à l''index %', v_ordinal;
    end;

    v_shift := coalesce(v_item->>'shift_id','');
    if v_shift not in ('urg-jour','urg-nuit','urg-24h') then
      raise exception 'Créneau invalide à l''index %', v_ordinal;
    end if;

    v_first := trim(coalesce(v_item->>'first_name',''));
    v_last := trim(coalesce(v_item->>'last_name',''));
    v_full := trim(coalesce(v_item->>'full_name', trim(v_first || ' ' || v_last)));
    v_norm_first := public.guardeflow_normalize_official_identity(v_first);
    v_norm_last := public.guardeflow_normalize_official_identity(v_last);
    if v_norm_first = '' or v_norm_last = '' then
      raise exception 'Prénom et nom complets requis à l''index %', v_ordinal;
    end if;

    v_guard_confidence := greatest(
      0,
      least(1, coalesce(nullif(v_item->>'confidence','')::numeric,0))
    );
    if v_guard_confidence < 0.90 then
      raise exception 'Garde à faible confiance à l''index %', v_ordinal;
    end if;

    v_review_status := lower(coalesce(v_item->>'review_status',v_status));
    if v_review_status not in ('green','orange') then
      raise exception 'Statut de garde non publiable à l''index %', v_ordinal;
    end if;

    v_match_status := case coalesce(v_item->>'match_status','unregistered')
      when 'matched' then 'matched'
      when 'ambiguous' then 'ambiguous'
      when 'manualReview' then 'manual_review'
      when 'manual_review' then 'manual_review'
      else 'unregistered'
    end;

    begin
      v_profile_id := nullif(v_item->>'matched_profile_id','')::uuid;
    exception when others then
      v_profile_id := null;
    end;

    select l.profile_id
    into v_link_profile_id
    from public.official_roster_identity_links l
    where l.active
      and l.hospital = coalesce(v_resource.hospital,'')
      and l.normalized_first_name = v_norm_first
      and l.normalized_last_name = v_norm_last
    limit 1;

    if v_link_profile_id is not null then
      v_profile_id := v_link_profile_id;
      v_match_status := 'matched';
    end if;

    if v_profile_id is not null then
      if not exists (
        select 1
        from public.profiles p
        where p.id = v_profile_id
          and p.account_status = 'active'
          and p.hospital = coalesce(v_resource.hospital,'')
      ) then
        v_profile_id := null;
        v_match_status := 'unregistered';
      end if;
    end if;

    begin
      v_page := nullif(v_item->>'page_number','')::int;
    exception when others then
      v_page := null;
    end;
    v_zone := nullif(trim(coalesce(v_item->>'zone','')),'');
    v_is_disciplinary := coalesce(
      nullif(v_item->>'is_disciplinary','')::boolean,
      false
    );

    insert into public.official_roster_guards(
      report_id,
      resource_id,
      resource_updated_at,
      parser_revision,
      source_ordinal,
      slot,
      hospital,
      date_str,
      shift_id,
      duty_area,
      first_name,
      last_name,
      full_name,
      normalized_first_name,
      normalized_last_name,
      page_number,
      zone,
      confidence,
      review_status,
      is_disciplinary,
      match_status,
      matched_profile_id,
      source_details
    ) values (
      v_report_id,
      v_resource.id,
      v_resource.updated_at,
      v_revision,
      v_ordinal,
      coalesce(v_resource.slot,''),
      coalesce(v_resource.hospital,''),
      v_date,
      v_shift,
      coalesce(nullif(v_item->>'duty_area',''),'urgences'),
      v_first,
      v_last,
      v_full,
      v_norm_first,
      v_norm_last,
      v_page,
      v_zone,
      v_guard_confidence,
      v_review_status,
      v_is_disciplinary,
      v_match_status,
      v_profile_id,
      v_item
    );
  end loop;

  for v_conflict in
    select value
    from jsonb_array_elements(coalesce(p_extraction->'conflicts','[]'::jsonb))
  loop
    begin
      v_date := nullif(v_conflict->>'date','')::date;
    exception when others then
      v_date := null;
    end;
    v_shift := nullif(v_conflict->>'shift','');

    insert into public.official_roster_anomalies(
      report_id,
      resource_id,
      resource_updated_at,
      parser_revision,
      anomaly_code,
      date_str,
      shift_id,
      page_number,
      zone,
      message,
      read_a,
      read_b,
      read_c,
      status,
      resolution,
      resolved_by,
      resolved_at
    ) values (
      v_report_id,
      v_resource.id,
      v_resource.updated_at,
      v_revision,
      coalesce(nullif(v_conflict->>'code',''),'read_conflict'),
      v_date,
      case
        when v_shift in ('urg-jour','urg-nuit','urg-24h') then v_shift
        else null
      end,
      coalesce(
        nullif(v_conflict->'a'->>'page_number','')::int,
        nullif(v_conflict->'b'->>'page_number','')::int,
        nullif(v_conflict->'c'->>'page_number','')::int
      ),
      coalesce(
        nullif(v_conflict->'a'->>'zone',''),
        nullif(v_conflict->'b'->>'zone',''),
        nullif(v_conflict->'c'->>'zone','')
      ),
      coalesce(nullif(v_conflict->>'message',''),'Désaccord de lecture'),
      coalesce(v_conflict->'a','{}'::jsonb),
      coalesce(v_conflict->'b','{}'::jsonb),
      v_conflict->'c',
      case
        when p_extraction->>'agreement' = 'ADMIN' then 'resolved_manual'
        else 'resolved_auto'
      end,
      jsonb_build_object(
        'agreement', p_extraction->>'agreement',
        'status', v_status,
        'manual_resolution', v_conflict->'resolution'
      ),
      auth.uid(),
      now()
    );
  end loop;

  update public.official_roster_import_reports r
  set
    doctor_count = (
      select count(distinct (g.normalized_first_name, g.normalized_last_name))::int
      from public.official_roster_guards g
      where g.report_id = v_report_id
    ),
    registered_doctors = (
      select count(distinct g.matched_profile_id)::int
      from public.official_roster_guards g
      where g.report_id = v_report_id
        and g.matched_profile_id is not null
    ),
    unregistered_doctors = (
      select count(distinct (g.normalized_first_name, g.normalized_last_name))::int
      from public.official_roster_guards g
      where g.report_id = v_report_id
        and g.match_status = 'unregistered'
    ),
    ambiguous_matches = (
      select count(*)::int
      from public.official_roster_guards g
      where g.report_id = v_report_id
        and g.match_status = 'ambiguous'
    ),
    manual_review_matches = (
      select count(*)::int
      from public.official_roster_guards g
      where g.report_id = v_report_id
        and g.match_status = 'manual_review'
    ),
    low_confidence_count = (
      select count(*)::int
      from public.official_roster_guards g
      where g.report_id = v_report_id
        and g.confidence < 0.90
    ),
    total_guards = (
      select count(*)::int
      from public.official_roster_guards g
      where g.report_id = v_report_id
    ),
    anomaly_count = (
      select count(*)::int
      from public.official_roster_anomalies a
      where a.report_id = v_report_id
    ),
    manual_correction_count = (
      select count(*)::int
      from public.official_roster_guards g
      where g.report_id = v_report_id
        and jsonb_array_length(g.correction_history) > 0
    ),
    updated_at = now()
  where r.id = v_report_id;

  select trim(coalesce(p.prenom,'') || ' ' || coalesce(p.nom,''))
  into v_actor_name
  from public.profiles p
  where p.id = auth.uid();

  insert into public.audit_log(
    actor_id,
    actor_name,
    action,
    entity_type,
    entity_id,
    reason,
    details
  ) values (
    auth.uid(),
    coalesce(nullif(v_actor_name,''),'Administrateur'),
    'official_roster_analysis_saved',
    'official_roster_import_report',
    v_report_id::text,
    'Analyse officielle R6 enregistrée',
    jsonb_build_object(
      'resource_id', p_resource_id,
      'resource_updated_at', p_resource_updated_at,
      'parser_revision', v_revision,
      'status', v_status,
      'confidence', v_confidence,
      'guard_count', jsonb_array_length(coalesce(p_guards,'[]'::jsonb))
    )
  );

  return (
    select to_jsonb(r)
    from public.official_roster_import_reports r
    where r.id = v_report_id
  );
end;
$$;

create or replace function public.admin_set_official_roster_identity_link(
  p_hospital text,
  p_first_name text,
  p_last_name text,
  p_full_name text,
  p_profile_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_norm_first text;
  v_norm_last text;
  v_profile public.profiles%rowtype;
  v_link_id uuid;
  v_before jsonb;
  v_after jsonb;
  v_actor_name text;
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;

  v_norm_first := public.guardeflow_normalize_official_identity(p_first_name);
  v_norm_last := public.guardeflow_normalize_official_identity(p_last_name);
  if v_norm_first = '' or v_norm_last = '' then
    raise exception 'Prénom et nom officiels requis';
  end if;

  select *
  into v_profile
  from public.profiles
  where id = p_profile_id
    and account_status = 'active';

  if not found then
    raise exception 'Compte médecin actif introuvable';
  end if;
  if v_profile.hospital is distinct from p_hospital then
    raise exception 'Le compte et l’identité officielle ne sont pas du même établissement';
  end if;

  select to_jsonb(l), l.id
  into v_before, v_link_id
  from public.official_roster_identity_links l
  where l.active
    and l.hospital = p_hospital
    and l.normalized_first_name = v_norm_first
    and l.normalized_last_name = v_norm_last
  limit 1
  for update;

  if v_link_id is null then
    insert into public.official_roster_identity_links(
      hospital,
      official_first_name,
      official_last_name,
      official_full_name,
      normalized_first_name,
      normalized_last_name,
      profile_id,
      active,
      created_by,
      updated_by,
      reason
    ) values (
      p_hospital,
      trim(p_first_name),
      trim(p_last_name),
      trim(coalesce(nullif(p_full_name,''), p_first_name || ' ' || p_last_name)),
      v_norm_first,
      v_norm_last,
      p_profile_id,
      true,
      auth.uid(),
      auth.uid(),
      p_reason
    )
    returning id into v_link_id;
  else
    update public.official_roster_identity_links
    set
      official_first_name = trim(p_first_name),
      official_last_name = trim(p_last_name),
      official_full_name = trim(
        coalesce(nullif(p_full_name,''), p_first_name || ' ' || p_last_name)
      ),
      profile_id = p_profile_id,
      active = true,
      updated_by = auth.uid(),
      updated_at = now(),
      reason = p_reason
    where id = v_link_id;
  end if;

  update public.official_roster_guards g
  set
    matched_profile_id = p_profile_id,
    match_status = 'matched',
    updated_at = now()
  where g.hospital = p_hospital
    and g.normalized_first_name = v_norm_first
    and g.normalized_last_name = v_norm_last;

  select to_jsonb(l)
  into v_after
  from public.official_roster_identity_links l
  where l.id = v_link_id;

  select trim(coalesce(p.prenom,'') || ' ' || coalesce(p.nom,''))
  into v_actor_name
  from public.profiles p
  where p.id = auth.uid();

  insert into public.audit_log(
    actor_id, actor_name, action, entity_type, entity_id,
    subject_id, subject_name, reason, details
  ) values (
    auth.uid(),
    coalesce(nullif(v_actor_name,''),'Administrateur'),
    'official_roster_identity_link_set',
    'official_roster_identity_link',
    v_link_id::text,
    p_profile_id,
    trim(v_profile.prenom || ' ' || v_profile.nom),
    p_reason,
    jsonb_build_object('before', v_before, 'after', v_after)
  );

  return v_after;
end;
$$;

create or replace function public.admin_delete_official_roster_identity_link(
  p_link_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_link public.official_roster_identity_links%rowtype;
  v_actor_name text;
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;

  select *
  into v_link
  from public.official_roster_identity_links
  where id = p_link_id
    and active
  for update;

  if not found then
    raise exception 'Liaison active introuvable';
  end if;

  update public.official_roster_identity_links
  set
    active = false,
    updated_by = auth.uid(),
    updated_at = now(),
    reason = p_reason
  where id = p_link_id;

  update public.official_roster_guards g
  set
    matched_profile_id = null,
    match_status = 'unregistered',
    updated_at = now()
  where g.hospital = v_link.hospital
    and g.normalized_first_name = v_link.normalized_first_name
    and g.normalized_last_name = v_link.normalized_last_name
    and g.matched_profile_id = v_link.profile_id;

  select trim(coalesce(p.prenom,'') || ' ' || coalesce(p.nom,''))
  into v_actor_name
  from public.profiles p
  where p.id = auth.uid();

  insert into public.audit_log(
    actor_id, actor_name, action, entity_type, entity_id,
    subject_id, reason, details
  ) values (
    auth.uid(),
    coalesce(nullif(v_actor_name,''),'Administrateur'),
    'official_roster_identity_link_deleted',
    'official_roster_identity_link',
    p_link_id::text,
    v_link.profile_id,
    p_reason,
    jsonb_build_object('before', to_jsonb(v_link))
  );
end;
$$;

create or replace function public.admin_correct_official_roster_guard(
  p_guard_id uuid,
  p_patch jsonb,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_guard public.official_roster_guards%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_date date;
  v_shift text;
  v_first text;
  v_last text;
  v_full text;
  v_norm_first text;
  v_norm_last text;
  v_actor_name text;
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;
  if trim(coalesce(p_reason,'')) = '' then
    raise exception 'Motif de correction requis';
  end if;

  select *
  into v_guard
  from public.official_roster_guards
  where id = p_guard_id
  for update;

  if not found then
    raise exception 'Garde officielle introuvable';
  end if;

  v_before := to_jsonb(v_guard);

  begin
    v_date := coalesce(nullif(p_patch->>'date','')::date, v_guard.date_str);
  exception when others then
    raise exception 'Date corrigée invalide';
  end;
  v_shift := coalesce(nullif(p_patch->>'shift_id',''), v_guard.shift_id);
  if v_shift not in ('urg-jour','urg-nuit','urg-24h') then
    raise exception 'Créneau corrigé invalide';
  end if;

  v_first := trim(coalesce(nullif(p_patch->>'first_name',''), v_guard.first_name));
  v_last := trim(coalesce(nullif(p_patch->>'last_name',''), v_guard.last_name));
  v_full := trim(
    coalesce(
      nullif(p_patch->>'full_name',''),
      nullif(v_guard.full_name,''),
      v_first || ' ' || v_last
    )
  );
  v_norm_first := public.guardeflow_normalize_official_identity(v_first);
  v_norm_last := public.guardeflow_normalize_official_identity(v_last);
  if v_norm_first = '' or v_norm_last = '' then
    raise exception 'Prénom et nom complets requis';
  end if;

  update public.official_roster_guards
  set
    date_str = v_date,
    shift_id = v_shift,
    first_name = v_first,
    last_name = v_last,
    full_name = v_full,
    normalized_first_name = v_norm_first,
    normalized_last_name = v_norm_last,
    confidence = 1,
    review_status = 'orange',
    matched_profile_id = null,
    match_status = 'unregistered',
    correction_history = correction_history || jsonb_build_array(
      jsonb_build_object(
        'at', now(),
        'by', auth.uid(),
        'reason', p_reason,
        'before', v_before,
        'patch', p_patch
      )
    ),
    updated_at = now()
  where id = p_guard_id;

  update public.official_roster_anomalies
  set
    status = 'resolved_manual',
    resolution = jsonb_build_object(
      'guard_id', p_guard_id,
      'patch', p_patch,
      'reason', p_reason
    ),
    resolved_by = auth.uid(),
    resolved_at = now()
  where report_id = v_guard.report_id
    and status = 'pending'
    and (date_str is null or date_str = v_guard.date_str)
    and (shift_id is null or shift_id = v_guard.shift_id);

  update public.official_roster_import_reports
  set
    manual_correction_count = (
      select count(*)::int
      from public.official_roster_guards g
      where g.report_id = v_guard.report_id
        and jsonb_array_length(g.correction_history) > 0
    ),
    status = 'orange',
    updated_at = now()
  where id = v_guard.report_id;

  select to_jsonb(g)
  into v_after
  from public.official_roster_guards g
  where g.id = p_guard_id;

  select trim(coalesce(p.prenom,'') || ' ' || coalesce(p.nom,''))
  into v_actor_name
  from public.profiles p
  where p.id = auth.uid();

  insert into public.audit_log(
    actor_id, actor_name, action, entity_type, entity_id,
    reason, details
  ) values (
    auth.uid(),
    coalesce(nullif(v_actor_name,''),'Administrateur'),
    'official_roster_guard_corrected',
    'official_roster_guard',
    p_guard_id::text,
    p_reason,
    jsonb_build_object('before', v_before, 'after', v_after)
  );

  return v_after;
end;
$$;

create or replace function public.admin_preview_official_roster_recalculation(
  p_profile_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles%rowtype;
  v_resource public.shared_resources%rowtype;
  v_preview jsonb;
  v_token text;
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;

  select *
  into v_profile
  from public.profiles
  where id = p_profile_id
    and account_status = 'active';

  if not found then
    raise exception 'Médecin actif introuvable';
  end if;

  select *
  into v_resource
  from public.shared_resources
  where kind = 'official_pdf'
    and hospital = v_profile.hospital
  order by updated_at desc
  limit 1;

  if not found then
    raise exception 'Aucun planning officiel actif pour cet établissement';
  end if;

  with target as (
    select
      g.id,
      g.date_str::text as date_str,
      g.shift_id,
      g.confidence,
      g.review_status,
      g.is_disciplinary,
      g.full_name
    from public.official_roster_guards g
    where g.resource_id = v_resource.id
      and g.resource_updated_at = v_resource.updated_at
      and g.matched_profile_id = p_profile_id
      and g.confidence >= 0.90
      and g.review_status in ('green','orange')
  ),
  current_entries as (
    select e.*
    from public.planning_entries e
    where e.owner_id = p_profile_id
      and e.deleted_at is null
  ),
  classified_target as (
    select
      t.*,
      e.id as current_entry_id,
      e.shift_id as current_shift_id,
      e.source_type as current_source_type,
      e.source_resource_id as current_source_resource_id,
      e.source_resource_updated_at as current_source_resource_updated_at,
      coalesce(pm.status,'draft') as month_status,
      public.guardeflow_is_past_month(t.date_str) as past_month
    from target t
    left join current_entries e on e.date_str = t.date_str
    left join public.planning_months pm
      on pm.owner_id = p_profile_id
      and pm.year = extract(year from t.date_str::date)::int
      and pm.month = extract(month from t.date_str::date)::int
  ),
  added as (
    select * from classified_target
    where current_entry_id is null
      and month_status <> 'approved'
      and not past_month
  ),
  unchanged as (
    select * from classified_target
    where current_entry_id is not null
      and current_shift_id = shift_id
      and current_source_type = 'official_emergency'
      and current_source_resource_id = v_resource.id
  ),
  modified as (
    select * from classified_target
    where current_entry_id is not null
      and current_shift_id <> shift_id
      and current_source_type = 'official_emergency'
      and current_source_resource_id = v_resource.id
      and month_status <> 'approved'
      and not past_month
  ),
  conflicts as (
    select * from classified_target
    where
      (current_entry_id is not null and
       coalesce(current_source_type,'') <> 'official_emergency')
      or month_status = 'approved'
      or past_month
  ),
  removed as (
    select e.*
    from current_entries e
    where e.source_type = 'official_emergency'
      and e.source_resource_id = v_resource.id
      and not exists (
        select 1 from target t where t.date_str = e.date_str
      )
      and not public.guardeflow_is_past_month(e.date_str)
      and coalesce((
        select pm.status
        from public.planning_months pm
        where pm.owner_id = p_profile_id
          and pm.year = extract(year from e.date_str)::int
          and pm.month = extract(month from e.date_str)::int
      ),'draft') <> 'approved'
  )
  select jsonb_build_object(
    'profile_id', p_profile_id,
    'profile_name', trim(v_profile.prenom || ' ' || v_profile.nom),
    'hospital', v_profile.hospital,
    'resource_id', v_resource.id,
    'resource_updated_at', v_resource.updated_at,
    'official_guard_count', (select count(*) from target),
    'added', coalesce((select jsonb_agg(to_jsonb(a) order by a.date_str) from added a),'[]'::jsonb),
    'modified', coalesce((select jsonb_agg(to_jsonb(m) order by m.date_str) from modified m),'[]'::jsonb),
    'removed', coalesce((select jsonb_agg(to_jsonb(r) order by r.date_str) from removed r),'[]'::jsonb),
    'unchanged', coalesce((select jsonb_agg(to_jsonb(u) order by u.date_str) from unchanged u),'[]'::jsonb),
    'conflicts', coalesce((select jsonb_agg(to_jsonb(c) order by c.date_str) from conflicts c),'[]'::jsonb)
  )
  into v_preview;

  v_token := md5(v_preview::text);

  return v_preview || jsonb_build_object('preview_token', v_token);
end;
$$;

create or replace function public.admin_apply_official_roster_recalculation(
  p_profile_id uuid,
  p_expected_preview_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_preview jsonb;
  v_token text;
  v_resource_id uuid;
  v_resource_updated_at timestamptz;
  v_assignments jsonb;
  v_result jsonb;
  v_run_id uuid;
  v_actor_name text;
  v_profile_name text;
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;

  v_preview := public.admin_preview_official_roster_recalculation(p_profile_id);
  v_token := v_preview->>'preview_token';
  if coalesce(v_token,'') = ''
     or v_token is distinct from p_expected_preview_token then
    raise exception 'L’aperçu a changé. Refaire l’aperçu avant application.';
  end if;

  v_resource_id := (v_preview->>'resource_id')::uuid;
  v_resource_updated_at := (v_preview->>'resource_updated_at')::timestamptz;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'profile_id', g.matched_profile_id,
        'date', g.date_str::text,
        'shift_id', g.shift_id,
        'is_disciplinary', g.is_disciplinary
      )
      order by g.date_str
    ),
    '[]'::jsonb
  )
  into v_assignments
  from public.official_roster_guards g
  where g.resource_id = v_resource_id
    and g.resource_updated_at = v_resource_updated_at
    and g.matched_profile_id = p_profile_id
    and g.confidence >= 0.90
    and g.review_status in ('green','orange');

  insert into public.official_roster_recalculation_runs(
    scope,
    profile_id,
    resource_id,
    resource_updated_at,
    requested_by,
    preview,
    preview_token
  ) values (
    'individual',
    p_profile_id,
    v_resource_id,
    v_resource_updated_at,
    auth.uid(),
    v_preview,
    v_token
  )
  returning id into v_run_id;

  -- Force a fresh profile-level derivation while keeping the R4/R5 import
  -- implementation and all its protection rules.
  delete from public.official_roster_profile_sync
  where resource_id = v_resource_id
    and resource_updated_at = v_resource_updated_at
    and profile_id = p_profile_id;

  begin
    v_result := public.import_official_emergency_roster_for_profile_v2(
      v_resource_id,
      v_resource_updated_at,
      p_profile_id,
      v_assignments,
      'v12.0.2-r6',
      '[]'::jsonb
    );

    update public.official_roster_recalculation_runs
    set
      applied = true,
      result = v_result,
      applied_at = now()
    where id = v_run_id;
  exception when others then
    update public.official_roster_recalculation_runs
    set error = sqlerrm
    where id = v_run_id;
    raise;
  end;

  select trim(coalesce(p.prenom,'') || ' ' || coalesce(p.nom,''))
  into v_actor_name
  from public.profiles p
  where p.id = auth.uid();

  select trim(coalesce(p.prenom,'') || ' ' || coalesce(p.nom,''))
  into v_profile_name
  from public.profiles p
  where p.id = p_profile_id;

  insert into public.audit_log(
    actor_id, actor_name, action, entity_type, entity_id,
    subject_id, subject_name, reason, details
  ) values (
    auth.uid(),
    coalesce(nullif(v_actor_name,''),'Administrateur'),
    'official_roster_recalculated',
    'official_roster_recalculation',
    v_run_id::text,
    p_profile_id,
    v_profile_name,
    'Recalcul individuel depuis la source officielle',
    jsonb_build_object(
      'preview', v_preview,
      'result', v_result,
      'source_unchanged', true
    )
  );

  return jsonb_build_object(
    'run_id', v_run_id,
    'preview', v_preview,
    'result', v_result
  );
end;
$$;

create or replace function public.admin_log_official_roster_global_recalculation(
  p_preview jsonb,
  p_result jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $
declare
  v_run_id uuid;
  v_token text;
  v_actor_name text;
begin
  if not public.is_admin() then
    raise exception 'Réservé à l’administrateur';
  end if;

  v_token := md5(coalesce(p_preview,'{}'::jsonb)::text);

  insert into public.official_roster_recalculation_runs(
    scope,
    requested_by,
    preview,
    preview_token,
    applied,
    result,
    applied_at
  ) values (
    'global',
    auth.uid(),
    coalesce(p_preview,'{}'::jsonb),
    v_token,
    true,
    coalesce(p_result,'{}'::jsonb),
    now()
  )
  returning id into v_run_id;

  select trim(coalesce(p.prenom,'') || ' ' || coalesce(p.nom,''))
  into v_actor_name
  from public.profiles p
  where p.id = auth.uid();

  insert into public.audit_log(
    actor_id, actor_name, action, entity_type, entity_id,
    reason, details
  ) values (
    auth.uid(),
    coalesce(nullif(v_actor_name,''),'Administrateur'),
    'official_roster_recalculated_global',
    'official_roster_recalculation',
    v_run_id::text,
    'Recalcul global depuis les sources officielles',
    jsonb_build_object(
      'preview', coalesce(p_preview,'{}'::jsonb),
      'result', coalesce(p_result,'{}'::jsonb),
      'source_unchanged', true
    )
  );

  return v_run_id;
end;
$;

revoke all on function public.save_official_roster_analysis_r6(
  uuid,timestamptz,jsonb,jsonb,jsonb
) from public;
revoke all on function public.admin_set_official_roster_identity_link(
  text,text,text,text,uuid,text
) from public;
revoke all on function public.admin_delete_official_roster_identity_link(
  uuid,text
) from public;
revoke all on function public.admin_correct_official_roster_guard(
  uuid,jsonb,text
) from public;
revoke all on function public.admin_preview_official_roster_recalculation(
  uuid
) from public;
revoke all on function public.admin_apply_official_roster_recalculation(
  uuid,text
) from public;
revoke all on function public.admin_log_official_roster_global_recalculation(
  jsonb,jsonb
) from public;

grant execute on function public.save_official_roster_analysis_r6(
  uuid,timestamptz,jsonb,jsonb,jsonb
) to authenticated;
grant execute on function public.admin_set_official_roster_identity_link(
  text,text,text,text,uuid,text
) to authenticated;
grant execute on function public.admin_delete_official_roster_identity_link(
  uuid,text
) to authenticated;
grant execute on function public.admin_correct_official_roster_guard(
  uuid,jsonb,text
) to authenticated;
grant execute on function public.admin_preview_official_roster_recalculation(
  uuid
) to authenticated;
grant execute on function public.admin_apply_official_roster_recalculation(
  uuid,text
) to authenticated;
grant execute on function public.admin_log_official_roster_global_recalculation(
  jsonb,jsonb
) to authenticated;

grant select on table public.official_roster_import_reports to authenticated;
grant select on table public.official_roster_guards to authenticated;
grant select on table public.official_roster_identity_links to authenticated;
grant select on table public.official_roster_anomalies to authenticated;
grant select on table public.official_roster_recalculation_runs to authenticated;

comment on table public.official_roster_guards is
  'Immutable-source interpretation of every official guard, including doctors without GardeFlow accounts. Personal calendars are derived separately.';
comment on table public.official_roster_identity_links is
  'Admin-confirmed persistent mapping from an official planning identity to a GardeFlow profile.';
comment on table public.official_roster_import_reports is
  'Traceable R6 import report with A/B/C status, completeness metrics and anomalies.';
