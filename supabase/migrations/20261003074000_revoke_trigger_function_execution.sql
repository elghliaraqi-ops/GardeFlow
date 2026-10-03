-- GardeFlow security hardening follow-up 2026-10-03
-- Trigger functions must not be callable directly through the Data API.

begin;

revoke execute on function public.clinical_case_enqueue_qcm_job()
  from public, anon, authenticated;

commit;
