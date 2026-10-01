create or replace function public.clinical_case_feed(p_offset integer default 0, p_limit integer default 20)
returns table(id uuid, age_band text, sex text, presentation text, history text, clinical_exam text, complementary_exams text, imaging_conclusion text, assessment text, plan text, disposition text, specialist_service text, qcm_question text, qcm_options jsonb, correct_index smallint, correction text, question_topic text, generation_source text, published_at timestamp with time zone, my_selected_index smallint, my_is_correct boolean, qcms jsonb)
language plpgsql
stable security definer
set search_path = 'public'
as $function$
declare v_uid uuid:=auth.uid();
begin
  if v_uid is null then raise exception 'Clinical cases: authentification requise.'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_uid and p.account_status='active') then
    raise exception 'Clinical cases: compte non actif.';
  end if;

  return query
  select
    c.id,c.age_band,c.sex,c.presentation,c.history,c.clinical_exam,c.complementary_exams,
    c.imaging_conclusion,c.assessment,c.plan,c.disposition,c.specialist_service,
    case when c.generation_source='openai' then c.qcm_question else '' end,
    case when c.generation_source='openai' then c.qcm_options else '[]'::jsonb end,
    case when c.generation_source='openai' and legacy.post_id is not null then c.correct_index else null::smallint end,
    case when c.generation_source='openai' and legacy.post_id is not null then c.correction else '' end,
    case when c.generation_source='openai' then c.question_topic else '' end,
    c.generation_source,c.published_at,legacy.selected_index,legacy.is_correct,
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',q.id,
          'position',q.position,
          'question',q.question,
          'options',q.options,
          'correct_index',case when ans.id is null then null else q.correct_index end,
          'correction',case when ans.id is null then '' else q.correction end,
          'topic',q.topic,
          'generation_source',q.generation_source,
          'my_selected_index',ans.selected_index,
          'my_is_correct',ans.is_correct,
          'answered_at',ans.answered_at
        ) order by q.position
      )
      from public.clinical_case_qcms q
      left join public.clinical_case_qcm_answers ans
        on ans.qcm_id=q.id and ans.user_id=v_uid
      where q.post_id=c.id
        and q.generation_source='openai'
    ),'[]'::jsonb)
  from public.clinical_case_posts c
  left join public.clinical_case_qcm_attempts legacy
    on legacy.post_id=c.id and legacy.user_id=v_uid
  order by c.published_at desc,c.id desc
  offset greatest(coalesce(p_offset,0),0)
  limit least(greatest(coalesce(p_limit,20),1),50);
end;
$function$;

revoke all on function public.clinical_case_feed(integer,integer) from public, anon;
grant execute on function public.clinical_case_feed(integer,integer) to authenticated, service_role;

revoke all on function public.clinical_case_submit_qcm_answer(uuid,smallint) from public, anon;
grant execute on function public.clinical_case_submit_qcm_answer(uuid,smallint) to authenticated, service_role;

revoke all on function public.clinical_case_mirror_first_qcm_answer() from public, anon, authenticated;
revoke all on function public.clinical_case_mirror_legacy_attempt() from public, anon, authenticated;
grant execute on function public.clinical_case_mirror_first_qcm_answer() to service_role;
grant execute on function public.clinical_case_mirror_legacy_attempt() to service_role;

revoke all on function public.set_my_appearance_theme(text) from public, anon;
grant execute on function public.set_my_appearance_theme(text) to authenticated, service_role;
