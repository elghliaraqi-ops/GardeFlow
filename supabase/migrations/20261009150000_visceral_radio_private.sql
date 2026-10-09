-- Private Viscéral × Radio training space; intentionally independent of official daily Practice.
create table if not exists public.practice_visceral_radio_sessions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  topic text not null,
  title text not null,
  fiche jsonb not null default '{}'::jsonb,
  course_qcms jsonb not null default '[]'::jsonb,
  case_data jsonb,
  case_qcms jsonb not null default '[]'::jsonb,
  case_target integer check(case_target in (10,15,20)),
  progress jsonb not null default '{}'::jsonb,
  medical_sources text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint visceral_radio_private_owner check (owner_id = 'a6ab90cd-aa2c-41f3-a5e8-be00aedd019c'::uuid)
);
create index if not exists practice_visceral_radio_owner_date_idx on public.practice_visceral_radio_sessions(owner_id, created_at desc);
alter table public.practice_visceral_radio_sessions enable row level security;
revoke all on public.practice_visceral_radio_sessions from anon;
grant select,insert,update,delete on public.practice_visceral_radio_sessions to authenticated;
create policy visceral_radio_owner_select on public.practice_visceral_radio_sessions for select to authenticated
  using (owner_id = (select auth.uid()) and owner_id = 'a6ab90cd-aa2c-41f3-a5e8-be00aedd019c'::uuid);
create policy visceral_radio_owner_insert on public.practice_visceral_radio_sessions for insert to authenticated
  with check(owner_id = (select auth.uid()) and owner_id = 'a6ab90cd-aa2c-41f3-a5e8-be00aedd019c'::uuid);
create policy visceral_radio_owner_update on public.practice_visceral_radio_sessions for update to authenticated
  using(owner_id = (select auth.uid()) and owner_id = 'a6ab90cd-aa2c-41f3-a5e8-be00aedd019c'::uuid)
  with check(owner_id = (select auth.uid()) and owner_id = 'a6ab90cd-aa2c-41f3-a5e8-be00aedd019c'::uuid);
create policy visceral_radio_owner_delete on public.practice_visceral_radio_sessions for delete to authenticated
  using(owner_id = (select auth.uid()) and owner_id = 'a6ab90cd-aa2c-41f3-a5e8-be00aedd019c'::uuid);
