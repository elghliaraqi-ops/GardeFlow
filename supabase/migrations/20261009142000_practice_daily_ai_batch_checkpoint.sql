-- Preserve validated daily AI batches across transient Groq failures.
-- Cache belongs to a challenge date and mode (shared daily generation, not a user score).
-- No access for regular clients; service_role Edge function only.
create table if not exists public.practice_daily_generation_batches (
 challenge_date date not null,
 mode text not null check (mode='cours_ia'),
 batch_index smallint not null check (batch_index between 0 and 1),
 questions jsonb not null check (
   jsonb_typeof(questions)='array' and
   jsonb_array_length(questions) between 1 and 5
 ),
 updated_at timestamptz not null default now(),
 primary key (challenge_date,mode,batch_index)
);
alter table public.practice_daily_generation_batches enable row level security;
revoke all on public.practice_daily_generation_batches from anon,authenticated;
comment on table public.practice_daily_generation_batches is
 'Private server-only staging of validated AI-generated daily QCMs. No user scores or image files.';
