-- GardeFlow — statuts médicaux à l'inscription (2026-10-08)
-- Déployer AVANT les builds Flutter qui lisent medical_position / training_year / training_language.
-- Non destructif : les anciens comptes conservent leurs grades et promotions.
-- Prévu pour le projet PlanningHM6 après vérification de la version du trigger.

begin;

alter table public.profiles
  add column if not exists medical_position text,
  add column if not exists training_year smallint,
  add column if not exists training_language text;

alter table public.profiles
  drop constraint if exists profiles_medical_position_check;
alter table public.profiles
  add constraint profiles_medical_position_check
  check (
    medical_position is null
    or medical_position in ('externe', 'ffi', 'interne', 'resident', 'professeur')
  );

alter table public.profiles
  drop constraint if exists profiles_training_language_check;
alter table public.profiles
  add constraint profiles_training_language_check
  check (
    (medical_position is null and training_language is null)
    or (medical_position is not null and training_language in ('francophone', 'anglophone'))
  );

alter table public.profiles
  drop constraint if exists profiles_training_year_by_position_check;
alter table public.profiles
  add constraint profiles_training_year_by_position_check
  check (
    (medical_position is null and training_year is null)
    or (medical_position in ('externe', 'resident') and training_year is not null and training_year between 1 and 5)
    or (medical_position = 'ffi' and training_year is not null and training_year in (6, 7))
    or (medical_position in ('interne', 'professeur') and training_year is null)
  );

-- N'inférer une promotion que pour les internes ou les comptes historiques
-- sans statut explicite, afin de ne pas attribuer une promotion à un externe/FFI/résident.
create or replace function public.sync_profile_promotion()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
begin
  if new.medical_position is not null and new.medical_position <> 'interne' then
    new.promotion_number := null;
    return new;
  end if;

  if coalesce(new.medical_grade, new.fonction, 'junior') = 'senior' then
    new.promotion_number := null;
    return new;
  end if;

  -- Les comptes historiques sans statut bénéficient encore de l'inférence.
  -- Une promotion expressément choisie n'est jamais écrasée.
  if new.promotion_number is null then
    new.promotion_number := public.infer_intern_promotion(new.nom, new.prenom);
  end if;
  return new;
end;
$function$;

-- Le statut médical modifié doit déclencher le recalcul/effacement de la
-- promotion, même si promotion_number n'est pas explicitement mis à jour.
drop trigger if exists profiles_sync_promotion on public.profiles;
create trigger profiles_sync_promotion
before insert or update of nom, prenom, promotion_number, medical_position
on public.profiles
for each row execute function public.sync_profile_promotion();

-- Conserver le workflow existant : rôle medecin, statut pending, validation admin.
-- Le grade est calculé côté serveur depuis le statut médical déclaré ; les
-- champs de user_metadata ne servent pas à des autorisations RLS.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  g text;
  v_position text;
  v_training_language text;
  v_training_year smallint;
  v_raw_training_year text;
  v_promotion smallint;
  v_raw_promotion text;
begin
  v_position := nullif(trim(coalesce(new.raw_user_meta_data->>'medical_position', '')), '');
  if v_position is not null and v_position not in
      ('externe', 'ffi', 'interne', 'resident', 'professeur') then
    raise exception 'Statut médical non reconnu';
  end if;

  if v_position is null then
    -- Compatibilité avec les anciennes versions de l'application.
    g := coalesce(new.raw_user_meta_data->>'medical_grade',
                  new.raw_user_meta_data->>'fonction', 'junior');
    if g not in ('junior', 'senior') then g := 'junior'; end if;
  else
    g := case when v_position = 'professeur' then 'senior' else 'junior' end;
  end if;

  v_training_language := nullif(
    trim(coalesce(new.raw_user_meta_data->>'training_language', '')), ''
  );
  if (v_position is not null and coalesce(v_training_language, '') not in ('francophone', 'anglophone'))
      or (v_position is null and v_training_language is not null
          and v_training_language not in ('francophone', 'anglophone')) then
    raise exception 'Langue de formation obligatoire : Francophone ou Anglophone';
  end if;

  v_training_year := null;
  v_raw_training_year := nullif(trim(coalesce(new.raw_user_meta_data->>'training_year', '')), '');
  if v_position in ('externe', 'ffi', 'resident') then
    if v_raw_training_year is null or v_raw_training_year !~ '^[0-9]{1,2}$' then
      raise exception 'Année d’études obligatoire';
    end if;
    v_training_year := v_raw_training_year::smallint;
    if (v_position in ('externe', 'resident') and v_training_year not between 1 and 5)
       or (v_position = 'ffi' and v_training_year not in (6, 7)) then
      raise exception 'Année d’études incompatible avec le statut';
    end if;
  elsif v_raw_training_year is not null then
    raise exception 'Année d’études non autorisée pour ce statut';
  end if;

  v_promotion := null;
  if (v_position is null and g = 'junior') or v_position = 'interne' then
    v_raw_promotion := nullif(trim(coalesce(new.raw_user_meta_data->>'promotion_number', '')), '');
    if v_raw_promotion ~ '^[0-9]{1,3}$' then
      v_promotion := v_raw_promotion::smallint;
      if v_promotion < 1 or v_promotion > 999 then
        v_promotion := null;
      end if;
    end if;
    if v_position = 'interne' and v_promotion is null then
      raise exception 'Promotion d’internat obligatoire';
    end if;
    if v_position is null then
      v_promotion := coalesce(
        v_promotion,
        public.infer_intern_promotion(
          coalesce(new.raw_user_meta_data->>'nom', ''),
          coalesce(new.raw_user_meta_data->>'prenom', '')
        )
      );
    end if;
  end if;

  insert into public.profiles (
    id, phone, nom, prenom, service, fonction, medical_grade, hospital,
    role, account_status, promotion_number, medical_position, training_year, training_language
  ) values (
    new.id,
    coalesce(new.phone, new.raw_user_meta_data->>'phone'),
    coalesce(new.raw_user_meta_data->>'nom', ''),
    coalesce(new.raw_user_meta_data->>'prenom', ''),
    coalesce(new.raw_user_meta_data->>'service', ''),
    g, g,
    coalesce(new.raw_user_meta_data->>'hospital', ''),
    'medecin',
    'pending',
    v_promotion,
    v_position,
    v_training_year,
    v_training_language
  )
  on conflict (id) do nothing;
  return new;
end;
$function$;

commit;
