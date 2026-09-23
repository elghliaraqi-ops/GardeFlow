-- GardeFlow V11.6.69 - paging order indexes
create index if not exists profiles_name_page_idx
  on public.profiles(prenom,nom,id);

create index if not exists planning_entries_active_date_page_idx
  on public.planning_entries(date_str,id)
  where deleted_at is null;

create index if not exists planning_months_date_page_idx
  on public.planning_months(year,month,owner_id);

create index if not exists exchange_requests_created_page_idx
  on public.exchange_requests(created_at,id);

create index if not exists leave_requests_created_page_idx
  on public.leave_requests(created_at,id);
