-- GardeFlow V11.6.1
-- Annuaire enrichi : contacts manuels administrateur + catégories.
-- À exécuter UNE FOIS dans Supabase > SQL Editor avant d'utiliser V11.6.1.

create table if not exists public.directory_contacts (
  id uuid primary key default gen_random_uuid(),
  category text not null check (
    category in (
      'medecins-seniors',
      'infirmiers',
      'flottes',
      'majors-superviseurs'
    )
  ),
  name text not null check (length(trim(name)) > 0),
  phone text not null check (length(trim(phone)) >= 4),
  hospital text not null,
  service text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists directory_contacts_hospital_category_idx
  on public.directory_contacts(hospital, category, name);

create unique index if not exists directory_contacts_hospital_phone_unique_idx
  on public.directory_contacts(hospital, phone);

alter table public.directory_contacts enable row level security;

drop policy if exists directory_contacts_read on public.directory_contacts;
create policy directory_contacts_read
on public.directory_contacts
for select
to authenticated
using (
  public.is_admin()
  or hospital = public.current_hospital()
);

drop policy if exists directory_contacts_admin_insert on public.directory_contacts;
create policy directory_contacts_admin_insert
on public.directory_contacts
for insert
to authenticated
with check (
  public.is_admin()
  and created_by = auth.uid()
);

drop policy if exists directory_contacts_admin_update on public.directory_contacts;
create policy directory_contacts_admin_update
on public.directory_contacts
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists directory_contacts_admin_delete on public.directory_contacts;
create policy directory_contacts_admin_delete
on public.directory_contacts
for delete
to authenticated
using (public.is_admin());

grant select, insert, update, delete
on public.directory_contacts
to authenticated;

-- Mise à jour instantanée de l’annuaire sur les appareils connectés.
do $$ begin
  alter publication supabase_realtime add table public.directory_contacts;
exception when duplicate_object then null; end $$;
