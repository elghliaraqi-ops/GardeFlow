-- Garde R6 database integration assertions.
-- This script is executed only against a disposable PostgreSQL instance.

\set ON_ERROR_STOP on

insert into public.profiles(
  id,phone,nom,prenom,service,fonction,hospital,role,medical_grade,account_status
) values
('11111111-1111-1111-1111-111111111111','+212600000001','Admin','R6','Imagerie','admin','Test Hospital','admin','junior','active'),
('22222222-2222-2222-2222-222222222222','+212600000002','Registered','Alice','Imagerie','junior','Test Hospital','medecin','junior','active');

insert into public.shared_resources(
  id,kind,slot,storage_path,display_name,mime_type,uploaded_by,updated_at,hospital
) values (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'official_pdf',
  'test_slot',
  'validation/test.pdf',
  'R6 CI validation.pdf',
  'application/pdf',
  '11111111-1111-1111-1111-111111111111',
  now(),
  'Test Hospital'
);

select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-1111-1111-111111111111',
  false
);

do $$
declare
  v_resource_updated_at timestamptz;
  v_day1 date := current_date + 5;
  v_day2 date := current_date + 6;
  v_report jsonb;
  v_preview jsonb;
  v_apply jsonb;
  v_before_hash text;
  v_after_hash text;
begin
  select updated_at into v_resource_updated_at
  from public.shared_resources
  where id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

  if exists (
    select 1
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public'
      and c.relname in (
        'official_roster_import_reports',
        'official_roster_guards',
        'official_roster_identity_links',
        'official_roster_anomalies',
        'official_roster_recalculation_runs'
      )
      and not c.relrowsecurity
  ) then
    raise exception 'R6 table exists without RLS';
  end if;

  if exists (
    select 1
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname in (
        'save_official_roster_analysis_r6',
        'admin_set_official_roster_identity_link',
        'admin_delete_official_roster_identity_link',
        'admin_correct_official_roster_guard',
        'admin_preview_official_roster_recalculation',
        'admin_apply_official_roster_recalculation',
        'admin_log_official_roster_global_recalculation'
      )
      and has_function_privilege('anon',p.oid,'EXECUTE')
  ) then
    raise exception 'anon can execute an R6 admin RPC';
  end if;

  v_report := public.save_official_roster_analysis_r6(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    v_resource_updated_at,
    jsonb_build_object(
      'verified',true,
      'status','green',
      'agreement','AB',
      'confidence',0.99,
      'parser_revision','v12.0.2-r6',
      'engine','ci',
      'rows',jsonb_build_array(
        jsonb_build_object('date',v_day1::text,'shift','urg-24h','page_number',1),
        jsonb_build_object('date',v_day2::text,'shift','urg-jour','page_number',1)
      ),
      'conflicts','[]'::jsonb,
      'validation_errors','[]'::jsonb,
      'read_summary',jsonb_build_object('c_executed',false)
    ),
    jsonb_build_array(
      jsonb_build_object(
        'date',v_day1::text,
        'shift_id','urg-24h',
        'hospital','Test Hospital',
        'first_name','Alice',
        'last_name','Registered',
        'full_name','Alice Registered',
        'confidence',0.99,
        'review_status','green',
        'page_number',1,
        'zone','CI registered',
        'is_disciplinary',false,
        'matched_profile_id','22222222-2222-2222-2222-222222222222',
        'match_status','matched'
      ),
      jsonb_build_object(
        'date',v_day2::text,
        'shift_id','urg-jour',
        'hospital','Test Hospital',
        'first_name','Bruno',
        'last_name','Unknown',
        'full_name','Bruno Unknown',
        'confidence',0.98,
        'review_status','green',
        'page_number',1,
        'zone','CI unregistered',
        'is_disciplinary',false,
        'matched_profile_id',null,
        'match_status','unregistered'
      )
    ),
    jsonb_build_array(
      jsonb_build_object(
        'date',v_day2::text,
        'shift_id','urg-jour',
        'text','Bruno Unknown',
        'reason','doctor_not_registered'
      )
    )
  );

  if (v_report->>'total_guards')::int <> 2 then
    raise exception 'Expected 2 official guards';
  end if;
  if (v_report->>'registered_doctors')::int <> 1 then
    raise exception 'Expected exactly 1 registered doctor';
  end if;
  if (v_report->>'unregistered_doctors')::int <> 1 then
    raise exception 'Expected exactly 1 unregistered doctor';
  end if;

  select md5(string_agg(
    concat_ws('|',id::text,date_str::text,shift_id,first_name,last_name,
              coalesce(matched_profile_id::text,''),match_status,
              confidence::text,review_status),
    '||' order by id
  ))
  into v_before_hash
  from public.official_roster_guards
  where resource_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

  v_preview := public.admin_preview_official_roster_recalculation(
    '22222222-2222-2222-2222-222222222222'
  );

  if jsonb_array_length(v_preview->'added') <> 1 then
    raise exception 'Preview must contain exactly 1 added guard';
  end if;

  v_apply := public.admin_apply_official_roster_recalculation(
    '22222222-2222-2222-2222-222222222222',
    v_preview->>'preview_token'
  );

  if coalesce((v_apply->>'ok')::boolean,false) is not true then
    raise exception 'Recalculation did not succeed';
  end if;

  if not exists (
    select 1 from public.planning_entries
    where owner_id='22222222-2222-2222-2222-222222222222'
      and date_str=v_day1
      and shift_id='urg-24h'
      and source_type='official_emergency'
      and deleted_at is null
  ) then
    raise exception 'Personal calendar was not rebuilt from official source';
  end if;

  select md5(string_agg(
    concat_ws('|',id::text,date_str::text,shift_id,first_name,last_name,
              coalesce(matched_profile_id::text,''),match_status,
              confidence::text,review_status),
    '||' order by id
  ))
  into v_after_hash
  from public.official_roster_guards
  where resource_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

  if v_before_hash is distinct from v_after_hash then
    raise exception 'Recalculation modified the official source';
  end if;

  begin
    perform public.admin_apply_official_roster_recalculation(
      '22222222-2222-2222-2222-222222222222',
      'stale-token'
    );
    raise exception 'Stale preview token unexpectedly accepted';
  exception
    when others then
      if sqlerrm = 'Stale preview token unexpectedly accepted' then
        raise;
      end if;
  end;

  begin
    perform public.save_official_roster_analysis_r6(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      v_resource_updated_at,
      '{"verified":true,"status":"red","confidence":0.99,"parser_revision":"v12.0.2-r6","rows":[],"conflicts":[],"validation_errors":[]}'::jsonb,
      '[]'::jsonb,
      '[]'::jsonb
    );
    raise exception 'RED import unexpectedly accepted';
  exception
    when others then
      if sqlerrm = 'RED import unexpectedly accepted' then
        raise;
      end if;
  end;

  begin
    perform public.save_official_roster_analysis_r6(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      v_resource_updated_at,
      jsonb_build_object(
        'verified',true,
        'status','green',
        'confidence',0.99,
        'parser_revision','v12.0.2-r6',
        'rows',jsonb_build_array(
          jsonb_build_object(
            'date',(current_date+8)::text,
            'shift','service-jour'
          )
        ),
        'conflicts','[]'::jsonb,
        'validation_errors','[]'::jsonb
      ),
      jsonb_build_array(
        jsonb_build_object(
          'date',(current_date+8)::text,
          'shift_id','service-jour',
          'hospital','Test Hospital',
          'first_name','Service',
          'last_name','Rejected',
          'full_name','Service Rejected',
          'confidence',0.99,
          'review_status','green',
          'matched_profile_id',null,
          'match_status','unregistered'
        )
      ),
      '[]'::jsonb
    );
    raise exception 'Service shift unexpectedly accepted by Urgences-only R6';
  exception
    when others then
      if sqlerrm = 'Service shift unexpectedly accepted by Urgences-only R6' then
        raise;
      end if;
  end;

  begin
    perform public.save_official_roster_analysis_r6(
      'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      v_resource_updated_at,
      jsonb_build_object(
        'verified',true,
        'status','green',
        'confidence',0.99,
        'parser_revision','v12.0.2-r6',
        'rows',jsonb_build_array(
          jsonb_build_object('date',(current_date+7)::text,'shift','urg-jour')
        ),
        'conflicts','[]'::jsonb,
        'validation_errors','[]'::jsonb
      ),
      jsonb_build_array(
        jsonb_build_object(
          'date',(current_date+7)::text,
          'shift_id','urg-jour',
          'hospital','Test Hospital',
          'first_name','Low',
          'last_name','Confidence',
          'full_name','Low Confidence',
          'confidence',0.89,
          'review_status','green',
          'matched_profile_id',null,
          'match_status','unregistered'
        )
      ),
      '[]'::jsonb
    );
    raise exception 'Low-confidence guard unexpectedly accepted';
  exception
    when others then
      if sqlerrm = 'Low-confidence guard unexpectedly accepted' then
        raise;
      end if;
  end;

  perform set_config(
    'request.jwt.claim.sub',
    '22222222-2222-2222-2222-222222222222',
    false
  );

  begin
    perform public.admin_preview_official_roster_recalculation(
      '22222222-2222-2222-2222-222222222222'
    );
    raise exception 'Non-admin unexpectedly accessed admin preview';
  exception
    when others then
      if sqlerrm = 'Non-admin unexpectedly accessed admin preview' then
        raise;
      end if;
  end;
end
$$;

select 'Garde R6 integration assertions passed' as result;
