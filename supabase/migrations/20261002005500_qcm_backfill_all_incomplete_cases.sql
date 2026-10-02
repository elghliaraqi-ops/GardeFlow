-- Re-open QCM generation for every published clinical case that does not have
-- a complete five-QCM set. This is intentionally provider-agnostic at the
-- historical-data level: existing complete QCM sets are preserved, while all
-- incomplete/failed cases (including old cases) become immediately eligible
-- for the current Gemini generator.
--
-- No QCM rows are deleted here. A successful generation remains atomically
-- committed by clinical_case_commit_generated_qcms.

with qcm_counts as (
  select
    p.id,
    count(q.id) filter (where q.generation_source = 'openai')::integer as qcm_count
  from public.clinical_case_posts p
  left join public.clinical_case_qcms q on q.post_id = p.id
  where p.published_at is not null
  group by p.id
), targets as (
  select id
  from qcm_counts
  where qcm_count <> 5
)
update public.clinical_case_posts p
set qcm_generation_status = 'idle',
    qcm_generation_attempts = 0,
    qcm_generation_started_at = null,
    qcm_generation_finished_at = null,
    qcm_generation_last_error = null,
    qcm_generation_retry_after = null,
    qcm_ai_provider = null
where p.id in (select id from targets);

with qcm_counts as (
  select
    p.id,
    count(q.id) filter (where q.generation_source = 'openai')::integer as qcm_count
  from public.clinical_case_posts p
  left join public.clinical_case_qcms q on q.post_id = p.id
  where p.published_at is not null
  group by p.id
), targets as (
  select id
  from qcm_counts
  where qcm_count <> 5
)
insert into public.clinical_case_qcm_generation_jobs(
  post_id,
  requested_by,
  status,
  started_at,
  finished_at,
  attempt_count,
  last_error_code,
  retry_after,
  updated_at
)
select
  id,
  null,
  'pending',
  null,
  null,
  0,
  null,
  null,
  now()
from targets
on conflict (post_id) do update
set requested_by = null,
    status = 'pending',
    started_at = null,
    finished_at = null,
    attempt_count = 0,
    last_error_code = null,
    retry_after = null,
    updated_at = now();
