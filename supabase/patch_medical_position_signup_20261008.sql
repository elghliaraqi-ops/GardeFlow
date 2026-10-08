-- GardeFlow — statuts médicaux à l'inscription (2026-10-08)
-- Déployer AVANT les builds Flutter qui lisent medical_position / training_year / training_language.
-- Non destructif : les anciens comptes conservent leurs grades et promotions.
-- Prévu pour le projet PlanningHM6 après vérification de la version du trigger.

begin;

-- Copie de sécurité strictement privée des profils avant migration.
-- Aucun accès au rôle anon/authenticated.
create table private.gardeflow_profiles_pre_medical_20261008 as
select * from public.profiles;
alter table private.gardeflow_profiles_pre_medical_20261008 enable row level security;
revoke all on table private.gardeflow_profiles_pre_medical_20261008
  from public, anon, authenticated;

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


-- Reprise explicite des 16 profils existants, sans toucher aux gardes ni aux rôles.
-- Comptes créés avant le 07/10 : internes francophones, promotions 5-7.
-- Exception contrôlée : Driss Douni était inscrit à tort en Promo 1 ;
-- le référentiel et la fonction d'inférence officielle le classent en Promo 7.
-- Les 4 nouveaux profils : 3 externes anglophones 4e année, 1 interne FR.
do $backfill$
declare
  v_first_promo smallint;
  v_count integer;
begin
  select current_first_year_promotion into v_first_promo
    from public.internship_promotion_config where id = 1;
  if v_first_promo is distinct from 7 then
    raise exception 'La promotion de première année a changé (%)', v_first_promo;
  end if;
  if (select count(*) from private.gardeflow_profiles_pre_medical_20261008) <> 16
     or (select count(*) from public.profiles) <> 16 then
    raise exception 'Nombre de profils inattendu : sauvegarde ou base';
  end if;
  if (select count(*) from public.profiles
        where (created_at at time zone 'Africa/Casablanca')::date < date '2026-10-07') <> 12 then
    raise exception 'Le lot de 12 anciens inscrits ne correspond pas';
  end if;
  if (select count(*) from public.profiles
        where (created_at at time zone 'Africa/Casablanca')::date = date '2026-10-07') <> 4 then
    raise exception 'Le lot des 4 nouveaux inscrits ne correspond pas';
  end if;
  if exists(
      select 1 from public.profiles where medical_grade <> 'junior'
        or fonction <> 'junior' or account_status <> 'active'
  ) then
    raise exception 'Les grades ou statuts des comptes ont changé : arrêt';
  end if;
  if exists (
      select 1 from public.profiles
      where (created_at at time zone 'Africa/Casablanca')::date < date '2026-10-07'
        and promotion_number not in (5,6,7)
        and not (
          lower(btrim(nom)) = 'douni'
          and lower(btrim(prenom)) = 'driss'
          and promotion_number = 1
          and public.infer_intern_promotion(nom,prenom) = 7
        )
  ) then
    raise exception 'Promotion ancienne hors 1re-3e année non reconnue';
  end if;
  if (select count(*) from public.profiles
        where lower(btrim(nom))='douni'
          and lower(btrim(prenom))='driss'
          and promotion_number=1) <> 1 then
    raise exception 'Le profil Driss Douni inattendu : arrêt';
  end if;
  if exists (
      select 1 from public.profiles
      where (created_at at time zone 'Africa/Casablanca')::date = date '2026-10-07'
        and not (
          (lower(btrim(nom))='meral' and lower(btrim(prenom))='taha')
          or (lower(btrim(nom))='miftah' and lower(btrim(prenom))='sara')
          or (lower(btrim(nom))='majjad' and lower(btrim(prenom))='wissal')
          or (lower(btrim(nom))='oukkas' and lower(btrim(prenom))='marwa')
        )
  ) then
    raise exception 'Inscription récente inconnue détectée : arrêt';
  end if;

  update public.profiles
  set medical_position = 'interne',
      training_language = 'francophone',
      training_year = null,
      promotion_number = case
        when lower(btrim(nom)) = 'douni'
         and lower(btrim(prenom)) = 'driss' then 7
        else promotion_number end
  where (created_at at time zone 'Africa/Casablanca')::date < date '2026-10-07';
  get diagnostics v_count = row_count;
  if v_count <> 12 then raise exception 'Anciens inscrits mis à jour : % sur 12', v_count; end if;

  update public.profiles
  set medical_position = 'externe',
      training_language = 'anglophone',
      training_year = 4,
      promotion_number = null
  where (created_at at time zone 'Africa/Casablanca')::date = date '2026-10-07'
    and (
        (lower(btrim(nom))='meral' and lower(btrim(prenom))='taha')
        or (lower(btrim(nom))='miftah' and lower(btrim(prenom))='sara')
        or (lower(btrim(nom))='majjad' and lower(btrim(prenom))='wissal')
    );
  get diagnostics v_count = row_count;
  if v_count <> 3 then raise exception 'Externes mis à jour : % sur 3', v_count; end if;

  update public.profiles
  set medical_position = 'interne',
      training_language = 'francophone',
      training_year = null,
      promotion_number = v_first_promo
  where (created_at at time zone 'Africa/Casablanca')::date = date '2026-10-07'
    and lower(btrim(nom))='oukkas' and lower(btrim(prenom))='marwa';
  get diagnostics v_count = row_count;
  if v_count <> 1 then raise exception 'Internes mis à jour : % sur 1', v_count; end if;

  if exists(
      select 1 from public.profiles
      where medical_position is null or training_language is null
      or (medical_position='interne' and promotion_number not in (5,6,7))
      or (medical_position='externe'
          and (training_year <> 4 or promotion_number is not null))
  ) then
    raise exception 'Incohérence détectée après modification : rollback';
  end if;
end;
$backfill$;

commit;
