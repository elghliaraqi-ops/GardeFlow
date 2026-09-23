-- GardeFlow 11.6.70 hotfix
-- La séparation Promo 6 / Promo 7 concerne uniquement les gardes d'Urgences.
-- Les transferts et échanges de Service restent autorisés entre promotions.

create or replace function public.enforce_exchange_promotion_scope()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  p_from smallint;
  p_to smallint;
  involves_urgences boolean;
begin
  select promotion_number into p_from from public.profiles where id=new.from_id;
  select promotion_number into p_to from public.profiles where id=new.to_id;

  involves_urgences := coalesce(new.shift_id, '') like 'urg-%'
    or (new.type = 'exchange' and coalesce(new.target_shift_id, '') like 'urg-%');

  if involves_urgences
     and p_from in (6,7)
     and p_to in (6,7)
     and p_from <> p_to then
    raise exception 'Les transferts et échanges de gardes d’Urgences sont interdits entre première année (Promo 7) et deuxième année (Promo 6)';
  end if;

  return new;
end;
$$;
