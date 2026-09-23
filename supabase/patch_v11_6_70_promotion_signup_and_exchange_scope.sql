-- GardeFlow v11.6.70
-- Promotion at signup + automatic internship-year label + Urgences exchange scope.
-- Applied to production on 2026-09-23.

begin;

create or replace function public.infer_intern_promotion(p_nom text, p_prenom text)
returns smallint
language plpgsql
immutable
set search_path to 'public', 'pg_temp'
as $$
declare
  k text := public.normalize_person_name(coalesce(p_nom,'') || ' ' || coalesce(p_prenom,''));
  r text := public.normalize_person_name(coalesce(p_prenom,'') || ' ' || coalesce(p_nom,''));
  promo5 text[] := array['najid saad','saad najid'];
  promo6 text[] := array[
    'aamer anas','abderrahmane elferdaous','adil lina','ahlsidimouloud aicha',
    'akdim aymen','amchaarou hamza','araqi el ghali','araqui houssaini elghali','araqui houssaini el ghali',
    'belhaj anas','bennani simo','bennour ghita','benzekri ines','bouhmouch ines',
    'bourkia wail','bouziane zineb','drifi salma','driouech selma','el baz daoud',
    'ezzine khadija','fassy fehry reda','hamich omar','imakor younes','imane norri',
    'ines khairi','iziraren yasmine','khaled hajar','laghdaf alia','latif idrissi fairouz',
    'maarouf aala','maryam elbardi','mellak omar','mourad ismail','moussa yahya','nouhaila aarab',
    'nyar malak','qossaim safaa','sahel ibtihal','sekkat kenza','serir ahmed','tary yasmine',
    'tlem aya','trabelsi salma','wiame khalifi','yazid marfoq','zaghrari dahmane',
    'zaghrari mohammed dahmane','zaghrari mohamed dahmane','mohammed dahmane zaghrari',
    'mohamed dahmane zaghrari','dahmane mohammed zaghrari','dahmane mohamed zaghrari',
    'zahid mohamed amine'
  ];
  promo7 text[] := array[
    'abbassi amine','ahjyage rim','albab salma','atassi salma','atassi souha','attou ilyas','bahaddi marwa',
    'bakertit hiba','bargache ghita','benakkouch reda','benaoda tlemcani mehdi','benattahellah mehdi',
    'benhalima ines','bennis ines','benomar meryem','benoufir salim','benzakour amine alia','berhili meryam',
    'berraho aya','bettach rania','bouchikhi lina','bourouda mounia','boutahri afaf','cabrane oumnia',
    'chadni manal','chamiti maria','channaoui imane','chaouki khawla','cheikh manal','cherkaoui meryem',
    'choklati aya','chraibi hamd','dami rime','dlimi nouha','douazi kenza','douni driss','el bardai badr',
    'el benna meriem','el eulj mohamed','el maazi ines','el merzougui yasmine','el mouden hamza','ennassiri ghaliya',
    'fatnane wissal','fenjiro rime','fetich ahmed','filali el garch lina','guessous imane','hadadia meryam',
    'hanafi nassima','harout salma','jebri ikrame','joundy jannate','khadraoui nour','khairi yasmine',
    'kouhen yassine','laabidi zakariae','laaroussi oumaima','lahroussi aymen','lasry youssef','lefriyekh omar',
    'lyamani rime','lyoubi idrissi soraya','maaden kaoutar','madi yazid','mahaouchi ayoub','mahboub chama',
    'majidi zineb','moussa aya','najah amine','nasri wiam','nasrollah fatima zahra','ouakani mohamed',
    'oukkas marwa','oulderrachid lalla hind','ouliou aya','oumary basma','outaleb nour alhouda','raissouni ghita',
    'raji loubna','rouissi maryem','sentissi badr eddine','serghat rania','tajri anas','youssefi yasmine','zahir ghita'
  ];
begin
  if k = any(promo7) or r = any(promo7) then return 7; end if;
  if k = any(promo6) or r = any(promo6) then return 6; end if;
  if k = any(promo5) or r = any(promo5) then return 5; end if;
  return null;
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

  v_promotion := null;
  if coalesce(new.raw_user_meta_data->>'promotion_number','') ~ '^[1-7]$' then
    v_promotion := (new.raw_user_meta_data->>'promotion_number')::smallint;
  end if;
  if g = 'senior' then v_promotion := null; end if;
  v_promotion := coalesce(
    v_promotion,
    public.infer_intern_promotion(
      coalesce(new.raw_user_meta_data->>'nom',''),
      coalesce(new.raw_user_meta_data->>'prenom','')
    )
  );

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

create or replace function public.enforce_exchange_promotion_scope()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
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
     and p_from is not null
     and p_to is not null
     and (
       (p_from = 7 and p_to between 1 and 6)
       or (p_to = 7 and p_from between 1 and 6)
     ) then
    raise exception 'Les gardes d’Urgences ne peuvent pas être transférées ou échangées entre un interne de première année (Promo 7) et un interne d’une promotion antérieure';
  end if;

  return new;
end;
$$;

update public.profiles
set promotion_number = 6
where public.normalize_person_name(coalesce(nom,'') || ' ' || coalesce(prenom,'')) in (
  'zaghrari mohammed dahmane','zaghrari mohamed dahmane'
)
or public.normalize_person_name(coalesce(prenom,'') || ' ' || coalesce(nom,'')) in (
  'mohammed dahmane zaghrari','mohamed dahmane zaghrari'
);

update public.profiles
set promotion_number = 5
where public.normalize_person_name(coalesce(nom,'') || ' ' || coalesce(prenom,'')) = 'najid saad'
   or public.normalize_person_name(coalesce(prenom,'') || ' ' || coalesce(nom,'')) = 'saad najid';

commit;
