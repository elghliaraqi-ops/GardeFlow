-- Report the actual eligible time for the next automatic AI generation.
-- After five failures, the worker waits 12 hours even if the initial
-- one-hour retry_after has elapsed. Do not mislead the reader with the
-- earlier timestamp; do not change the provider cooldown or force a retry.
create or replace function public.clinical_case_qcm_worker_statuses()
returns table(
  post_id uuid,
  status text,
  attempt_count integer,
  retry_after timestamptz,
  last_error_code text
)
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null or not exists(
    select 1 from public.profiles p
    where p.id = v_uid and p.account_status = 'active'
  ) then
    raise exception 'Active authentication required';
  end if;
  return query
    select p.id,
           case
             when exists (
               select 1 from public.clinical_case_qcms q
               where q.post_id = p.id and q.generation_source = 'openai'
             ) then 'ready'::text
             else coalesce(j.status, 'idle'::text)
           end,
           coalesce(j.attempt_count, 0),
           case
             when j.status = 'failed'
               and j.attempt_count >= 5
               and j.retry_after is not null
               and j.last_error_code in (
                 'literature_sources_unavailable',
                 'groq_provider_unavailable', 'groq_rate_limited',
                 'groq_timeout', 'groq_network_error', 'groq_invalid_json',
                 'groq_json_validate_failed', 'generation_failed',
                 'database_write_failed'
               )
             then greatest(j.retry_after, j.updated_at + interval '12 hours')
             else j.retry_after
           end,
           j.last_error_code
    from public.clinical_case_posts p
    left join public.clinical_case_qcm_generation_jobs j
      on j.post_id = p.id
    where p.published_at is not null
    order by p.published_at desc
    limit 500;
end;
$$;
revoke all on function public.clinical_case_qcm_worker_statuses() from public, anon;
grant execute on function public.clinical_case_qcm_worker_statuses() to authenticated;
