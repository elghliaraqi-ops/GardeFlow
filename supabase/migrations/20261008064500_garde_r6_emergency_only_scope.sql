-- GardeFlow R6 scope lock: official roster engine handles Urgences only.

alter table public.official_roster_guards
  drop constraint if exists official_roster_guards_duty_area_check;

alter table public.official_roster_guards
  add constraint official_roster_guards_duty_area_check
  check (duty_area = 'urgences');
