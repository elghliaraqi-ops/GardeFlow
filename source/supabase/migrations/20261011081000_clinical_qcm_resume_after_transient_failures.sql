-- Keep automatic clinical QCM generation alive without creating a
-- provider request storm. Initial attempts: max five with backoff. After
-- exhaustion, retry ONE transient failure at most every 12 hours.
-- Never retry invalid requests/auth failures.
create or replace function public.clinical_case_worker_claim_next()
returns table(post_id uuid, requested_by uuid, attempt_count integer)
language plpgsql security definer
set search_path=public,pg_temp
as $$
declare
 v_post_id uuid;
 v_requested_by uuid;
 v_attempt integer;
begin
 select j.post_id, coalesce(j.requested_by,p.author_id),j.attempt_count+1
 into v_post_id,v_requested_by,v_attempt
 from public.clinical_case_qcm_generation_jobs j
 join public.clinical_case_posts p on p.id=j.post_id
 where p.published_at is not null
   and (
     j.attempt_count < 5
     or (
       j.attempt_count >= 5
       and j.updated_at < now()-interval '12 hours'
       and (
         (j.status='failed' and j.last_error_code in (
           'literature_sources_unavailable','groq_provider_unavailable',
           'groq_rate_limited','groq_timeout','groq_network_error',
           'groq_invalid_json','groq_json_validate_failed',
           'generation_failed','database_write_failed'
         ))
         or (j.status='running' and j.started_at < now()-interval '12 hours')
       )
     )
   )
   and (
     j.status='pending'
     or (j.status='failed' and j.retry_after is not null
         and j.retry_after<=now())
     or (j.status='running' and j.started_at is not null
         and j.started_at<now()-interval '3 minutes')
   )
   and (select count(*) from public.clinical_case_qcms q
        where q.post_id=j.post_id and q.generation_source='openai')<5
 order by p.published_at asc,j.updated_at asc
 for update of j skip locked
 limit 1;
 if v_post_id is null then return;end if;
 update public.clinical_case_qcm_generation_jobs
 set requested_by=v_requested_by,status='running',
     started_at=now(),finished_at=null,attempt_count=v_attempt,
     last_error_code=null,retry_after=null,updated_at=now()
 where clinical_case_qcm_generation_jobs.post_id=v_post_id;
 update public.clinical_case_posts
 set qcm_generation_status='running',qcm_generation_attempts=v_attempt,
     qcm_generation_started_at=now(),qcm_generation_finished_at=null,
     qcm_generation_last_error=null,qcm_generation_retry_after=null
 where clinical_case_posts.id=v_post_id;
 return query select v_post_id,v_requested_by,v_attempt;
end;
$$;
