-- Align server-only daily challenge checkpoints with the 10-QCM single-call Groq generator.
-- Preserve old 1..5-question checkpoints; newer requests can atomically cache all 10.
-- This changes only the JSON array cardinality check: no row deletion, no RLS changes.
alter table public.practice_daily_generation_batches
  drop constraint if exists practice_daily_generation_batches_questions_check;
alter table public.practice_daily_generation_batches
  add constraint practice_daily_generation_batches_questions_check
  check (
    jsonb_typeof(questions) = 'array'
    and jsonb_array_length(questions) between 1 and 10
  );
comment on table public.practice_daily_generation_batches is
  'Private service_role-only staging for up to 10 validated daily AI QCMs per checkpoint; no image bytes or user scores.';
