-- GardeFlow - Programme du bloc
-- Sécurise les documents "bloc_program" par établissement sans modifier
-- les règles existantes des autres ressources partagées.
-- À appliquer uniquement après validation de la branche feature.

drop policy if exists shared_resources_read on public.shared_resources;
create policy shared_resources_read
on public.shared_resources
for select
to authenticated
using (
  public.current_account_active()
  and (
    kind <> 'bloc_program'
    or public.is_admin()
    or hospital = (
      select p.hospital
      from public.profiles p
      where p.id = auth.uid()
        and p.account_status = 'active'
      limit 1
    )
  )
);

drop policy if exists gardeflow_shared_read on storage.objects;
create policy gardeflow_shared_read
on storage.objects
for select
to authenticated
using (
  bucket_id = 'gardeflow-shared'
  and public.current_account_active()
  and (
    name not like 'bloc-programs/%'
    or public.is_admin()
    or name like (
      'bloc-programs/' ||
      case (
        select p.hospital
        from public.profiles p
        where p.id = auth.uid()
          and p.account_status = 'active'
        limit 1
      )
        when 'Hôpital Universitaire International Mohammed VI de Bouskoura'
          then 'hm6_bouskoura'
        when 'Hôpital Universitaire International Mohammed VI de Rabat'
          then 'hm6_rabat'
        when 'Hôpital Universitaire International Cheikh Khalifa de Casablanca'
          then 'hck_casa'
        else '__no_hospital__'
      end ||
      '/%'
    )
  )
);
