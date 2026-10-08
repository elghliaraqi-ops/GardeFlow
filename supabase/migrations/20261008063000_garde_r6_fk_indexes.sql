-- Additive R6 performance indexes discovered during isolated validation.

create index if not exists official_roster_reports_imported_by_idx
  on public.official_roster_import_reports(imported_by);

create index if not exists official_roster_guards_report_id_idx
  on public.official_roster_guards(report_id);

create index if not exists official_roster_guards_matched_profile_idx
  on public.official_roster_guards(matched_profile_id);

create index if not exists official_roster_identity_links_created_by_idx
  on public.official_roster_identity_links(created_by);

create index if not exists official_roster_identity_links_updated_by_idx
  on public.official_roster_identity_links(updated_by);

create index if not exists official_roster_anomalies_resource_idx
  on public.official_roster_anomalies(resource_id, resource_updated_at);

create index if not exists official_roster_anomalies_resolved_by_idx
  on public.official_roster_anomalies(resolved_by);

create index if not exists official_roster_recalc_resource_idx
  on public.official_roster_recalculation_runs(
    resource_id,
    resource_updated_at,
    created_at desc
  );

create index if not exists official_roster_recalc_requested_by_idx
  on public.official_roster_recalculation_runs(requested_by, created_at desc);
