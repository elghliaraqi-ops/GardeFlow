-- Promotion is an intern/junior concept. Senior profiles must never inherit an intern promotion.
create or replace function public.sync_profile_promotion()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $$
begin
  if coalesce(new.medical_grade, new.fonction, 'junior') = 'senior' then
    new.promotion_number := null;
    return new;
  end if;

  if new.promotion_number is null
     or new.nom is distinct from old.nom
     or new.prenom is distinct from old.prenom then
    new.promotion_number := coalesce(
      public.infer_intern_promotion(new.nom, new.prenom),
      new.promotion_number
    );
  end if;
  return new;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  g text;
  v_promotion smallint;
begin
  g := coalesce(new.raw_user_meta_data->>'medical_grade', new.raw_user_meta_data->>'fonction', 'junior');
  if g not in ('junior','senior') then g := 'junior'; end if;

  if g = 'senior' then
    v_promotion := null;
  else
    v_promotion := null;
    if coalesce(new.raw_user_meta_data->>'promotion_number','') ~ '^[1-7]$' then
      v_promotion := (new.raw_user_meta_data->>'promotion_number')::smallint;
    end if;
    v_promotion := coalesce(
      v_promotion,
      public.infer_intern_promotion(
        coalesce(new.raw_user_meta_data->>'nom',''),
        coalesce(new.raw_user_meta_data->>'prenom','')
      )
    );
  end if;

  insert into public.profiles(
    id,phone,nom,prenom,service,fonction,medical_grade,hospital,role,account_status,promotion_number
  ) values (
    new.id,
    coalesce(new.phone,new.raw_user_meta_data->>'phone'),
    coalesce(new.raw_user_meta_data->>'nom',''),
    coalesce(new.raw_user_meta_data->>'prenom',''),
    coalesce(new.raw_user_meta_data->>'service',''),
    g,
    g,
    coalesce(new.raw_user_meta_data->>'hospital',''),
    'medecin',
    'pending',
    v_promotion
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
