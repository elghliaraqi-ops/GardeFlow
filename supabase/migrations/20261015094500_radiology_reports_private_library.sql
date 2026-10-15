-- Private reports from the GardeFlow radiology assistant.
-- No identifiable patient demographic columns or previous reports are stored.
create table if not exists public.radiology_reports (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  exam_type text not null check (char_length(exam_type) between 1 and 80),
  region text not null check (char_length(region) between 1 and 240),
  indication text not null check (char_length(indication) between 1 and 3500),
  exam_date date,
  report_text text not null check (char_length(report_text) between 1 and 30000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.radiology_reports is
  'Private, physician-authored radiology report drafts; one authenticated owner per report.';

create index if not exists radiology_reports_owner_created_idx
  on public.radiology_reports (owner_id, created_at desc);
create index if not exists radiology_reports_owner_exam_date_idx
  on public.radiology_reports (owner_id, exam_date desc);
create index if not exists radiology_reports_owner_type_idx
  on public.radiology_reports (owner_id, exam_type);

create or replace function public.touch_radiology_report_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
revoke all on function public.touch_radiology_report_updated_at() from public, anon;
grant execute on function public.touch_radiology_report_updated_at() to authenticated;

drop trigger if exists radiology_reports_touch_updated_at on public.radiology_reports;
create trigger radiology_reports_touch_updated_at
  before update on public.radiology_reports
  for each row execute function public.touch_radiology_report_updated_at();

alter table public.radiology_reports enable row level security;
revoke all privileges on table public.radiology_reports from public, anon, authenticated;
grant select, insert on public.radiology_reports to authenticated;
grant update (exam_type, region, indication, exam_date, report_text)
  on public.radiology_reports to authenticated;

drop policy if exists radiology_reports_select_own on public.radiology_reports;
create policy radiology_reports_select_own on public.radiology_reports
  for select to authenticated
  using (owner_id = (select auth.uid()));

drop policy if exists radiology_reports_insert_own on public.radiology_reports;
create policy radiology_reports_insert_own on public.radiology_reports
  for insert to authenticated
  with check (owner_id = (select auth.uid()));

drop policy if exists radiology_reports_update_own on public.radiology_reports;
create policy radiology_reports_update_own on public.radiology_reports
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));
