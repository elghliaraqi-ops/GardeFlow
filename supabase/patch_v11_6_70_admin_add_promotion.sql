-- GardeFlow v11.6.70
-- Promotion management:
-- - Promo 7 remains the current first-year cohort until an admin adds a new promo.
-- - The promotion config is readable before login so registration can keep a dropdown in sync.
-- - Only an active GardeFlow admin can increment the official first-year promotion.
-- - The increment is atomic and future promotions require no app code change.

revoke all on table public.internship_promotion_config from anon;
grant select on table public.internship_promotion_config to anon;

revoke insert, delete, truncate, references, trigger
on table public.internship_promotion_config
from authenticated;
grant select, update on table public.internship_promotion_config to authenticated;

drop policy if exists internship_promotion_config_read
on public.internship_promotion_config;
create policy internship_promotion_config_read
on public.internship_promotion_config
for select
to anon, authenticated
using (true);

drop policy if exists internship_promotion_config_admin_update
on public.internship_promotion_config;
create policy internship_promotion_config_admin_update
on public.internship_promotion_config
for update
to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'
      and p.account_status = 'active'
  )
)
with check (
  exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'
      and p.account_status = 'active'
  )
);

create or replace function public.admin_add_internship_promotion()
returns smallint
language sql
security invoker
set search_path = 'public', 'pg_temp'
as $$
  update public.internship_promotion_config
  set current_first_year_promotion = current_first_year_promotion + 1,
      updated_at = now()
  where id = 1
  returning current_first_year_promotion;
$$;

revoke execute on function public.admin_add_internship_promotion()
from public, anon;
grant execute on function public.admin_add_internship_promotion()
to authenticated;
