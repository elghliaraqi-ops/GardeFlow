-- Each generated progressive simulation belongs to one authenticated doctor.
-- Never store image files or actual patient data (fictional training only).
create table if not exists public.practice_generated_cases (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id) on delete cascade,
 specialty text not null check (char_length(specialty) between 2 and 100),
 case_title text not null check (char_length(case_title) between 1 and 180),
 case_stem text not null check (char_length(case_stem) between 150 and 6500),
 case_stages jsonb not null check (
  jsonb_typeof(case_stages)='array' and jsonb_array_length(case_stages)=4
 ),
 questions jsonb not null check (
  jsonb_typeof(questions)='array' and jsonb_array_length(questions)=10
 ),
 created_at timestamptz not null default now()
);
create index if not exists practice_generated_cases_owner_created_idx
 on public.practice_generated_cases (owner_id, created_at desc);
alter table public.practice_generated_cases enable row level security;
drop policy if exists practice_generated_cases_read_own
 on public.practice_generated_cases;
create policy practice_generated_cases_read_own
 on public.practice_generated_cases for select to authenticated
 using (owner_id = (select auth.uid()));
-- Case creation is server-only after validation; clients cannot forge AI cases.
revoke all on table public.practice_generated_cases from anon, authenticated;
grant select on table public.practice_generated_cases to authenticated;
comment on table public.practice_generated_cases is
 'Private AI-generated fictional progressive clinical cases; remote image URLs only.';
