-- Track the actual LLM provider independently from the legacy
-- generation_source='openai' compatibility flag used by the current client/RPCs.
-- This lets GardeFlow switch providers without triggering regeneration loops.

alter table public.clinical_case_qcms
  add column if not exists ai_provider text;

alter table public.clinical_case_posts
  add column if not exists qcm_ai_provider text;

alter table public.clinical_case_qcm_generation_jobs
  add column if not exists ai_provider text;

comment on column public.clinical_case_qcms.ai_provider is
  'Actual provider used to generate the QCM, e.g. openai or deepseek.';

comment on column public.clinical_case_posts.qcm_ai_provider is
  'Actual provider used for the latest successful five-QCM generation.';

comment on column public.clinical_case_qcm_generation_jobs.ai_provider is
  'Provider selected for the latest generation attempt.';
