-- GardeFlow V11.6.59
-- Annuaire complet accessible à tous les médecins actifs.
-- La table profiles garde ses règles actuelles : seule une RPC dédiée expose
-- les champs strictement utiles à l'annuaire.

drop function if exists public.directory_contacts_all();

create function public.directory_contacts_all()
returns table(
  id uuid,
  category text,
  name text,
  phone text,
  hospital text,
  service text,
  grade_label text,
  is_admin boolean,
  is_manual boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    case
      when p.medical_grade = 'senior' then 'medecins-seniors'
      else 'medecins-juniors'
    end as category,
    trim(coalesce(p.prenom,'') || ' ' || coalesce(p.nom,'')) as name,
    p.phone,
    p.hospital,
    p.service,
    case
      when p.medical_grade = 'senior' then 'Sénior'
      else 'Junior'
    end as grade_label,
    (p.role = 'admin') as is_admin,
    false as is_manual
  from public.profiles p
  where auth.uid() is not null
    and public.current_account_active()
    and p.account_status = 'active'
    and nullif(trim(p.phone),'') is not null

  union all

  select
    d.id,
    d.category,
    d.name,
    d.phone,
    d.hospital,
    d.service,
    null::text as grade_label,
    false as is_admin,
    true as is_manual
  from public.directory_contacts d
  where auth.uid() is not null
    and public.current_account_active()

  order by hospital, category, name;
$$;

revoke all on function public.directory_contacts_all()
  from public, anon;
grant execute on function public.directory_contacts_all()
  to authenticated;

drop policy if exists directory_contacts_read on public.directory_contacts;
create policy directory_contacts_read
on public.directory_contacts
for select
to authenticated
using (
  auth.uid() is not null
  and public.current_account_active()
);
