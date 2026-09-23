-- GardeFlow 11.6.70
-- Fil public d'annonces de gardes + séparation Promo 7 (1re année) / Promo 6 (2e année).

begin;

alter table public.profiles
  add column if not exists promotion_number smallint;

alter table public.profiles
  drop constraint if exists profiles_promotion_number_check;
alter table public.profiles
  add constraint profiles_promotion_number_check
  check (promotion_number is null or promotion_number between 1 and 7);

create or replace function public.infer_intern_promotion(p_nom text, p_prenom text)
returns smallint
language plpgsql
immutable
set search_path=public,pg_temp
as $$
declare
  k text := public.normalize_person_name(coalesce(p_nom,'') || ' ' || coalesce(p_prenom,''));
  r text := public.normalize_person_name(coalesce(p_prenom,'') || ' ' || coalesce(p_nom,''));
  promo6 text[] := array[
    'aamer anas','abderrahmane elferdaous','adil lina','ahlsidimouloud aicha','akdim aymen','amchaarou hamza','araqi el ghali','belhaj anas',
    'bennani simo','bennour ghita','benzekri ines','bouhmouch ines','bourkia wail','bouziane zineb','drifi salma','driouech selma','el baz daoud','ezzine khadija',
    'fassy fehry reda','hamich omar','imakor younes','imane norri','ines khairi','iziraren yasmine','khaled hajar','laghdaf alia','latif idrissi fairouz','maarouf aala',
    'maryam elbardi','mellak omar','mourad ismail','moussa yahya','nouhaila aarab','nyar malak','qossaim safaa','sahel ibtihal','sekkat kenza','serir ahmed',
    'tary yasmine','tlem aya','trabelsi salma','wiame khalifi','yazid marfoq','zaghrari dahmane','zahid mohamed amine'
  ];
  promo7 text[] := array[
    'abbassi amine','ahjyage rim','albab salma','atassi salma','atassi souha','attou ilyas','bahaddi marwa','bakertit hiba','bargache ghita','benakkouch reda',
    'benaoda tlemcani mehdi','benattahellah mehdi','benhalima ines','bennis ines','benomar meryem','benoufir salim','benzakour amine alia','berhili meryam',
    'berraho aya','bettach rania','bouchikhi lina','bourouda mounia','boutahri afaf','cabrane oumnia','chadni manal','chamiti maria','channaoui imane','chaouki khawla',
    'cheikh manal','cherkaoui meryem','choklati aya','chraibi hamd','dami rime','dlimi nouha','douazi kenza','douni driss','el bardai badr','el benna meriem',
    'el eulj mohamed','el maazi ines','el merzougui yasmine','el mouden hamza','ennassiri ghaliya','fatnane wissal','fenjiro rime','fetich ahmed','filali el garch lina',
    'guessous imane','hadadia meryam','hanafi nassima','harout salma','jebri ikrame','joundy jannate','khadraoui nour','khairi yasmine','kouhen yassine','laabidi zakariae',
    'laaroussi oumaima','lahroussi aymen','lasry youssef','lefriyekh omar','lyamani rime','lyoubi idrissi soraya','maaden kaoutar','madi yazid','mahaouchi ayoub','mahboub chama',
    'majidi zineb','moussa aya','najah amine','nasri wiam','nasrollah fatima zahra','ouakani mohamed','oukkas marwa','oulderrachid lalla hind','ouliou aya','oumary basma',
    'outaleb nour alhouda','raissouni ghita','raji loubna','rouissi maryem','sentissi badr eddine','serghat rania','tajri anas','youssefi yasmine','zahir ghita'
  ];
begin
  if k = any(promo7) or r = any(promo7) then return 7; end if;
  if k = any(promo6) or r = any(promo6) then return 6; end if;
  return null;
end;
$$;

create or replace function public.sync_profile_promotion()
returns trigger
language plpgsql
set search_path=public,pg_temp
as $$
begin
  if new.promotion_number is null or new.nom is distinct from old.nom or new.prenom is distinct from old.prenom then
    new.promotion_number := coalesce(public.infer_intern_promotion(new.nom,new.prenom), new.promotion_number);
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_sync_promotion on public.profiles;
create trigger profiles_sync_promotion
before insert or update of nom,prenom,promotion_number on public.profiles
for each row execute function public.sync_profile_promotion();

update public.profiles
set promotion_number = public.infer_intern_promotion(nom,prenom)
where public.infer_intern_promotion(nom,prenom) is not null
  and promotion_number is distinct from public.infer_intern_promotion(nom,prenom);

create or replace function public.enforce_exchange_promotion_scope()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  p_from smallint;
  p_to smallint;
begin
  select promotion_number into p_from from public.profiles where id=new.from_id;
  select promotion_number into p_to from public.profiles where id=new.to_id;
  if p_from in (6,7) and p_to in (6,7) and p_from <> p_to then
    raise exception 'Les transferts et échanges sont interdits entre première année (Promo 7) et deuxième année (Promo 6)';
  end if;
  return new;
end;
$$;

drop trigger if exists exchange_promotion_scope_guard on public.exchange_requests;
create trigger exchange_promotion_scope_guard
before insert or update of from_id,to_id,status on public.exchange_requests
for each row execute function public.enforce_exchange_promotion_scope();

create table if not exists public.public_announcements (
  id text primary key,
  author_id uuid not null references public.profiles(id) on delete cascade,
  author_name text not null,
  hospital text not null,
  promotion_number smallint,
  planning_entry_id text not null references public.planning_entries(id) on delete cascade,
  date_str date not null,
  shift_id text not null,
  message text not null default '',
  created_at timestamptz not null default now(),
  closed_at timestamptz,
  constraint public_announcements_promotion_check
    check (promotion_number is null or promotion_number between 1 and 7),
  constraint public_announcements_message_length
    check (char_length(message) <= 280)
);

create index if not exists public_announcements_created_at_idx
  on public.public_announcements(created_at desc);
create index if not exists public_announcements_date_idx
  on public.public_announcements(date_str);
create unique index if not exists public_announcements_one_active_per_guard_idx
  on public.public_announcements(planning_entry_id)
  where closed_at is null;

alter table public.public_announcements enable row level security;

drop policy if exists public_announcements_select on public.public_announcements;
create policy public_announcements_select on public.public_announcements
for select to authenticated
using (public.current_account_active());

drop policy if exists public_announcements_insert on public.public_announcements;
create policy public_announcements_insert on public.public_announcements
for insert to authenticated
with check (
  public.current_account_active()
  and author_id=auth.uid()
  and closed_at is null
  and exists (
    select 1
    from public.profiles p
    where p.id=auth.uid()
      and p.account_status='active'
      and p.hospital=public_announcements.hospital
      and p.promotion_number is not distinct from public_announcements.promotion_number
  )
  and exists (
    select 1
    from public.planning_entries e
    where e.id=public_announcements.planning_entry_id
      and e.owner_id=auth.uid()
      and e.deleted_at is null
      and e.shift_id<>'conge'
      and coalesce(e.is_disciplinary,false)=false
      and e.date_str=public_announcements.date_str
      and e.shift_id=public_announcements.shift_id
      and not public.guard_has_started(e.date_str,e.shift_id)
      and public.planning_month_is_approved(e.owner_id,e.date_str)
  )
);

drop policy if exists public_announcements_update on public.public_announcements;
create policy public_announcements_update on public.public_announcements
for update to authenticated
using (
  public.current_account_active()
  and (author_id=auth.uid() or public.is_admin())
)
with check (
  public.current_account_active()
  and (author_id=auth.uid() or public.is_admin())
);

drop policy if exists public_announcements_delete on public.public_announcements;
create policy public_announcements_delete on public.public_announcements
for delete to authenticated
using (
  public.current_account_active()
  and (author_id=auth.uid() or public.is_admin())
);

create or replace function public.protect_public_announcement_update()
returns trigger
language plpgsql
set search_path=public,pg_temp
as $$
begin
  if new.id is distinct from old.id
     or new.author_id is distinct from old.author_id
     or new.author_name is distinct from old.author_name
     or new.hospital is distinct from old.hospital
     or new.promotion_number is distinct from old.promotion_number
     or new.planning_entry_id is distinct from old.planning_entry_id
     or new.date_str is distinct from old.date_str
     or new.shift_id is distinct from old.shift_id
     or new.message is distinct from old.message
     or new.created_at is distinct from old.created_at then
    raise exception 'Seule la fermeture d’une annonce est modifiable';
  end if;
  return new;
end;
$$;

drop trigger if exists public_announcement_update_guard on public.public_announcements;
create trigger public_announcement_update_guard
before update on public.public_announcements
for each row execute function public.protect_public_announcement_update();

do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime')
     and not exists(
       select 1 from pg_publication_tables
       where pubname='supabase_realtime'
         and schemaname='public'
         and tablename='public_announcements'
     ) then
    alter publication supabase_realtime add table public.public_announcements;
  end if;
end $$;

commit;