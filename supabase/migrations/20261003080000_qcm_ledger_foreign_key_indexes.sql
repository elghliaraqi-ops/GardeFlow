-- GardeFlow post-merge performance hardening 2026-10-03
-- Cover the two foreign keys on the private immutable QCM ledger.

begin;

create index if not exists qcm_response_events_qcm_id_idx
  on private.clinical_case_qcm_response_events(qcm_id);

create index if not exists qcm_response_events_post_id_idx
  on private.clinical_case_qcm_response_events(post_id);

commit;
