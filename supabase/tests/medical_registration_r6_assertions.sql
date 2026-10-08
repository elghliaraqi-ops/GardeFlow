-- Combined SQL assertions run on disposable Postgres after R6 assertions
-- and schema migration. Never run on production: inserts synthetic test users.
\set ON_ERROR_STOP on
begin;
insert into public.profiles(
  id,phone,nom,prenom,service,fonction,hospital,role,medical_grade,account_status,
  medical_position,training_year,training_language,promotion_number
) values
  ('33333333-3333-3333-3333-333333333333','+212600000003','TestExt','English','Test','junior','Test Hospital','medecin','junior','active','externe',4,'anglophone',7),
  ('44444444-4444-4444-4444-444444444444','+212600000004','TestIntern','French','Test','junior','Test Hospital','medecin','junior','active','interne',null,'francophone',7),
  ('55555555-5555-5555-5555-555555555555','+212600000005','TestProfessor','Senior','Test','senior','Test Hospital','medecin','senior','active','professeur',null,'francophone',null);

do $medical$
begin
  if not exists (
    select 1 from public.profiles
    where id='33333333-3333-3333-3333-333333333333'
      and medical_position='externe' and training_year=4
      and training_language='anglophone' and promotion_number is null
      and medical_grade='junior'
  ) then
    raise exception 'Externe: wrong grade/year/language or promotion not cleared';
  end if;
  if not exists (
    select 1 from public.profiles
    where id='44444444-4444-4444-4444-444444444444'
      and medical_position='interne' and training_language='francophone'
      and training_year is null and promotion_number=7
  ) then
    raise exception 'Interne: promotion not preserved';
  end if;
  if not exists (
    select 1 from public.profiles
    where id='55555555-5555-5555-5555-555555555555'
      and medical_position='professeur' and training_language='francophone'
      and training_year is null and promotion_number is null
  ) then
    raise exception 'Professeur: wrong category';
  end if;

  begin
    insert into public.profiles (
      id,phone,nom,prenom,hospital,medical_position,training_year,training_language
    ) values (
      '66666666-6666-6666-6666-666666666666','+212600000006',
      'Test','MissingYear','Test Hospital','ffi',null,'francophone'
    );
    raise exception 'Missing training year unexpectedly accepted';
  exception when check_violation then null;
  end;

  begin
    insert into public.profiles (
      id,phone,nom,prenom,hospital,medical_position,training_year,training_language
    ) values (
      '77777777-7777-7777-7777-777777777777','+212600000007',
      'Test','MissingLanguage','Test Hospital','resident',2,null
    );
    raise exception 'Missing language unexpectedly accepted';
  exception when check_violation then null;
  end;

  begin
    insert into public.profiles (
      id,phone,nom,prenom,hospital,medical_position,training_year,training_language
    ) values (
      '88888888-8888-8888-8888-888888888888','+212600000008',
      'Test','InvalidFFI','Test Hospital','ffi',5,'francophone'
    );
    raise exception 'FFI fifth year unexpectedly accepted';
  exception when check_violation then null;
  end;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='admin_apply_official_roster_recalculation'
  ) then
    raise exception 'R6 recalculation RPC lost during medical registration migration';
  end if;
  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='official_roster_guards'
  ) then
    raise exception 'R6 official roster table lost during medical registration migration';
  end if;
end
$medical$;

rollback;
select 'Combined R6 + medical registration assertions passed' as result;
