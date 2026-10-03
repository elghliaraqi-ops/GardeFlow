-- GardeFlow hardening follow-up 2026-10-03
-- Existing approved planning months predate approval_source metadata.
-- Mark them explicitly as legacy for auditability without changing their state.

begin;

update public.planning_months
set approval_source = 'legacy'
where status = 'approved'
  and approval_source is null;

commit;
