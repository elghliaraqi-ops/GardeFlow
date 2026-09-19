-- GardeFlow V11.6.53
-- Resynchronisation manuelle du PDF officiel + application serveur des règles
-- disciplinaires déjà détectées dans le document.

create or replace function public.reset_my_official_roster_profile_sync(
  p_resource_id uuid,
  p_resource_updated_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  r public.shared_resources%rowtype;
  p public.profiles%rowtype;
  expected_hospital text;
begin
  if uid is null then raise exception 'Session requise'; end if;

  select * into r
  from public.shared_resources
  where id=p_resource_id and kind='official_pdf';

  if not found then raise exception 'Planning officiel introuvable'; end if;
  if r.updated_at is distinct from p_resource_updated_at then
    raise exception 'Le PDF a été remplacé. Actualisez la page.';
  end if;

  select * into p
  from public.profiles
  where id=uid and account_status='active';

  if not found then raise exception 'Profil actif introuvable'; end if;

  expected_hospital := case r.slot
    when 'hm6_bouskoura' then 'Hôpital Universitaire International Mohammed VI de Bouskoura'
    when 'hm6_rabat' then 'Hôpital Universitaire International Mohammed VI de Rabat'
    when 'hck_casa' then 'Hôpital Universitaire International Cheikh Khalifa de Casablanca'
    else null
  end;

  if expected_hospital is null or p.hospital is distinct from expected_hospital then
    raise exception 'Ce planning officiel ne correspond pas à votre établissement';
  end if;

  delete from public.official_roster_profile_sync
  where resource_id=p_resource_id
    and resource_updated_at=p_resource_updated_at
    and profile_id=uid;
end;
$$;

grant execute on function public.reset_my_official_roster_profile_sync(uuid,timestamptz)
  to authenticated;

create or replace function public.apply_current_disciplinary_rules_for_me()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  p public.profiles%rowtype;
  m record;
  existing public.planning_entries%rowtype;
  inserted_count int := 0;
  updated_count int := 0;
  matched_rules int := 0;
begin
  if uid is null then raise exception 'Session requise'; end if;

  select * into p
  from public.profiles
  where id=uid and account_status='active'
  for update;

  if not found then raise exception 'Profil actif introuvable'; end if;

  perform set_config('gardeflow.official_import','1',true);

  for m in
    select
      r.date_str,
      r.shift_id,
      r.resource_id,
      r.resource_updated_at
    from public.official_disciplinary_name_rules r
    join public.shared_resources sr
      on sr.id=r.resource_id
     and sr.kind='official_pdf'
     and sr.updated_at=r.resource_updated_at
    where public.profile_matches_disciplinary_rule(uid,r.date_str,r.normalized_red_text)
      and (
        (sr.slot='hm6_bouskoura' and p.hospital='Hôpital Universitaire International Mohammed VI de Bouskoura')
        or (sr.slot='hm6_rabat' and p.hospital='Hôpital Universitaire International Mohammed VI de Rabat')
        or (sr.slot='hck_casa' and p.hospital='Hôpital Universitaire International Cheikh Khalifa de Casablanca')
      )
    order by r.date_str
  loop
    matched_rules := matched_rules + 1;

    insert into public.official_disciplinary_guards(
      owner_id,date_str,shift_id,resource_id,resource_updated_at,detected_at
    )
    values(
      uid,m.date_str,m.shift_id,m.resource_id,m.resource_updated_at,now()
    )
    on conflict(owner_id,date_str,resource_id,resource_updated_at)
    do update
      set shift_id=excluded.shift_id,
          detected_at=now();

    select * into existing
    from public.planning_entries
    where owner_id=uid
      and date_str=m.date_str
      and deleted_at is null
    order by created_at desc
    limit 1
    for update;

    if found then
      update public.exchange_requests
      set status='cancelled'
      where status in ('pendingB','pendingAdmin')
        and (
          planning_entry_id=existing.id
          or target_planning_entry_id=existing.id
        );

      update public.planning_entries
      set shift_id=m.shift_id,
          owner_phone=p.phone,
          owner_name=trim(coalesce(p.prenom,'') || ' ' || coalesce(p.nom,'')),
          leave_request_id=null,
          source_type='official_emergency',
          source_resource_id=m.resource_id,
          source_resource_updated_at=m.resource_updated_at,
          is_disciplinary=true
      where id=existing.id;

      updated_count := updated_count + 1;
    else
      insert into public.planning_entries(
        id,date_str,shift_id,owner_id,owner_phone,owner_name,created_at,
        source_type,source_resource_id,source_resource_updated_at,is_disciplinary
      )
      values(
        'pdf-' || replace(gen_random_uuid()::text,'-',''),
        m.date_str,m.shift_id,uid,p.phone,
        trim(coalesce(p.prenom,'') || ' ' || coalesce(p.nom,'')),
        now(),
        'official_emergency',m.resource_id,m.resource_updated_at,true
      );

      inserted_count := inserted_count + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'matched_rules',matched_rules,
    'inserted',inserted_count,
    'updated',updated_count
  );
end;
$$;

grant execute on function public.apply_current_disciplinary_rules_for_me()
  to authenticated;
