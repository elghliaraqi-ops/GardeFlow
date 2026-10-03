-- GardeFlow DB regression assertions for the 2026-10-03 hardening.
-- Intended for `supabase test db` / psql in a disposable environment.

begin;

select plan(8);

select ok(
  exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='planning_months'
      and column_name='auto_validation_blocked'
  ),
  'planning_months has an explicit auto-validation hold'
);

select ok(
  exists(
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='review_planning_month'
  ),
  'admin planning review RPC exists'
);

select ok(
  exists(
    select 1 from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where not t.tgisinternal and n.nspname='public'
      and c.relname='exchange_requests'
      and t.tgname='exchange_promotion_scope_guard'
  ),
  'promotion scope trigger remains active'
);

select ok(
  exists(
    select 1 from information_schema.tables
    where table_schema='private'
      and table_name='clinical_case_qcm_response_events'
  ),
  'private immutable QCM event ledger exists'
);

select is(
  (select count(*)::bigint from private.clinical_case_qcm_response_events),
  (select count(*)::bigint from public.clinical_case_qcm_answer_history),
  'initial event-ledger backfill preserves every historical first answer'
);

select ok(
  not has_table_privilege('anon','private.clinical_case_qcm_response_events','SELECT'),
  'anon cannot read private QCM event ledger'
);

select ok(
  not has_table_privilege('authenticated','private.clinical_case_qcm_response_events','SELECT'),
  'authenticated clients cannot directly read private QCM event ledger'
);

select ok(
  has_function_privilege('authenticated','public.clinical_case_qcm_stats()','EXECUTE'),
  'authenticated users can only reach QCM stats through the hardened RPC'
);

select * from finish();
rollback;
