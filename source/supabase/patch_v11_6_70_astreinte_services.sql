-- GardeFlow - classement des photos d'astreinte senior par service.
alter table public.shared_resources
  add column if not exists service text;

update public.shared_resources
set service = 'À classer'
where kind = 'astreinte_photo'
  and (service is null or btrim(service) = '');

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'shared_resources_astreinte_service_required'
      and conrelid = 'public.shared_resources'::regclass
  ) then
    alter table public.shared_resources
      add constraint shared_resources_astreinte_service_required
      check (
        kind <> 'astreinte_photo'
        or (service is not null and btrim(service) <> '')
      );
  end if;
end $$;

create index if not exists shared_resources_astreinte_hospital_service_idx
  on public.shared_resources(hospital, service, updated_at desc)
  where kind = 'astreinte_photo';

drop policy if exists shared_resources_admin_update on public.shared_resources;
create policy shared_resources_admin_update
on public.shared_resources
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

comment on column public.shared_resources.service is
  'Service hospitalier associé à une photo d’astreinte senior. Null pour les autres ressources.';
