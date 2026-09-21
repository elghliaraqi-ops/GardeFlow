-- GardeFlow V11.6.2
-- Ajoute la catégorie « Extensions » à l'annuaire existant.
-- À exécuter UNE FOIS après le patch V11.6.1.

alter table public.directory_contacts
  drop constraint if exists directory_contacts_category_check;

alter table public.directory_contacts
  add constraint directory_contacts_category_check
  check (
    category in (
      'medecins-seniors',
      'infirmiers',
      'flottes',
      'majors-superviseurs',
      'extensions'
    )
  );
