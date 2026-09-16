-- GardeFlow V11.6.6
-- Galeries des médecins séniors d'astreinte séparées par hôpital,
-- mais visibles par TOUS les médecins authentifiés.
-- Les photos historiques existantes sont rattachées à HUIM6 Bouskoura.

alter table public.shared_resources
  add column if not exists hospital text;

-- Toutes les photos d'astreinte déjà présentes avant V11.6.6 appartiennent
-- à HUIM6 Bouskoura, comme convenu.
update public.shared_resources
set hospital = 'Hôpital Universitaire International Mohammed VI de Bouskoura'
where kind = 'astreinte_photo'
  and (hospital is null or btrim(hospital) = '');

-- Les PDF officiels continuent d'utiliser la colonne slot et ne nécessitent
-- pas de valeur hospital dans cette nouvelle colonne.
update public.shared_resources
set hospital = null
where kind = 'official_pdf';

-- Contrainte idempotente : une photo d'astreinte doit appartenir à l'un des
-- trois hôpitaux ; les PDF officiels gardent hospital à NULL.
do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conname = 'shared_resources_hospital_check'
      and conrelid = 'public.shared_resources'::regclass
  ) then
    alter table public.shared_resources
      drop constraint shared_resources_hospital_check;
  end if;

  alter table public.shared_resources
    add constraint shared_resources_hospital_check
    check (
      (kind = 'astreinte_photo' and hospital in (
        'Hôpital Universitaire International Mohammed VI de Bouskoura',
        'Hôpital Universitaire International Mohammed VI de Rabat',
        'Hôpital Universitaire International Cheikh Khalifa de Casablanca'
      ))
      or
      (kind = 'official_pdf' and hospital is null)
    );
end $$;

create index if not exists shared_resources_astreinte_hospital_updated_idx
  on public.shared_resources(hospital, updated_at desc)
  where kind = 'astreinte_photo';

-- Lecture : tous les utilisateurs authentifiés peuvent consulter les trois galeries.
alter table public.shared_resources enable row level security;

drop policy if exists shared_resources_read on public.shared_resources;
create policy shared_resources_read
on public.shared_resources
for select
to authenticated
using (true);

-- Écriture/suppression : toujours réservées aux administrateurs.
drop policy if exists shared_resources_admin_insert on public.shared_resources;
create policy shared_resources_admin_insert
on public.shared_resources
for insert
to authenticated
with check (public.is_admin() and uploaded_by = auth.uid());

drop policy if exists shared_resources_admin_update on public.shared_resources;
create policy shared_resources_admin_update
on public.shared_resources
for update
to authenticated
using (public.is_admin())
with check (public.is_admin() and uploaded_by = auth.uid());

drop policy if exists shared_resources_admin_delete on public.shared_resources;
create policy shared_resources_admin_delete
on public.shared_resources
for delete
to authenticated
using (public.is_admin());

grant select, insert, update, delete on public.shared_resources to authenticated;

-- Le bucket reste privé : tous les comptes authentifiés lisent,
-- seuls les admins peuvent ajouter/modifier/supprimer des fichiers.
drop policy if exists gardeflow_shared_read on storage.objects;
create policy gardeflow_shared_read
on storage.objects
for select
to authenticated
using (bucket_id = 'gardeflow-shared');

drop policy if exists gardeflow_shared_admin_insert on storage.objects;
create policy gardeflow_shared_admin_insert
on storage.objects
for insert
to authenticated
with check (bucket_id = 'gardeflow-shared' and public.is_admin());

drop policy if exists gardeflow_shared_admin_update on storage.objects;
create policy gardeflow_shared_admin_update
on storage.objects
for update
to authenticated
using (bucket_id = 'gardeflow-shared' and public.is_admin())
with check (bucket_id = 'gardeflow-shared' and public.is_admin());

drop policy if exists gardeflow_shared_admin_delete on storage.objects;
create policy gardeflow_shared_admin_delete
on storage.objects
for delete
to authenticated
using (bucket_id = 'gardeflow-shared' and public.is_admin());

-- Contrôle facultatif après exécution :
-- select kind, hospital, count(*)
-- from public.shared_resources
-- group by kind, hospital
-- order by kind, hospital;
