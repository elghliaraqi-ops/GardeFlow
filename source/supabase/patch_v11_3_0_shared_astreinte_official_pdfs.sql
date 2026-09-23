-- GardeFlow V11.3.0
-- Photos d'astreinte partagées + trois PDF de planning officiel.
-- À exécuter une seule fois dans Supabase > SQL Editor.

create extension if not exists pgcrypto;

-- Métadonnées des fichiers partagés. Les octets vivent dans Supabase Storage.
create table if not exists public.shared_resources (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('astreinte_photo','official_pdf')),
  slot text,
  storage_path text not null unique,
  display_name text not null,
  mime_type text not null,
  uploaded_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (kind='astreinte_photo' and slot is null)
    or
    (kind='official_pdf' and slot in ('hm6_bouskoura','hm6_rabat','hck_casa'))
  )
);

-- Un seul PDF courant par établissement/slot. Les photos restent multiples
-- car PostgreSQL autorise plusieurs NULL dans une contrainte UNIQUE.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'shared_resources_kind_slot_key'
      and conrelid = 'public.shared_resources'::regclass
  ) then
    alter table public.shared_resources
      add constraint shared_resources_kind_slot_key unique (kind, slot);
  end if;
end $$;

create index if not exists shared_resources_kind_updated_idx
  on public.shared_resources(kind, updated_at desc);

alter table public.shared_resources enable row level security;

drop policy if exists shared_resources_read on public.shared_resources;
create policy shared_resources_read
on public.shared_resources
for select
to authenticated
using (true);

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

grant select on public.shared_resources to authenticated;
grant insert, update, delete on public.shared_resources to authenticated;

-- Bucket privé : les fichiers ne sont pas anonymement publics. Tous les comptes
-- connectés peuvent les lire ; seuls les administrateurs peuvent écrire/supprimer.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'gardeflow-shared',
  'gardeflow-shared',
  false,
  26214400,
  array['image/jpeg','image/png','image/webp','application/pdf']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

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
