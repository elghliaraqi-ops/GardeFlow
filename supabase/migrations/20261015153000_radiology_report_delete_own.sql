-- Physician-owned reports can be removed by their owner only.
-- No broad DELETE grant on any other GardeFlow table.
grant delete on public.radiology_reports to authenticated;
drop policy if exists radiology_reports_delete_own on public.radiology_reports;
create policy radiology_reports_delete_own on public.radiology_reports
  for delete to authenticated
  using (owner_id = (select auth.uid()));
