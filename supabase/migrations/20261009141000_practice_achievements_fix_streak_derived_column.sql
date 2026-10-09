-- Emergency hotfix: prevent practice_my_achievements() from raising undefined_column
-- due to the derived table exposing "day" and not "challenge_date".
-- This migration updates only the function. No DELETE, TRUNCATE, DROP,
-- reset of XP, removal of badges, or mutation of historical achievement rows.
create or replace function public.practice_refresh_my_achievements()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
 uid uuid := (select auth.uid());
 a record;
 progress_value integer;
 total_patients integer := 0;
 total_complete integer := 0;
 total_specialist integer := 0;
 total_guards integer := 0;
 current_streak integer := 0;
 qcm_answered integer := 0;
 qcm_correct integer := 0;
 clinical_xp integer := 0;
 combined_xp integer := 0;
 standalone_cases integer := 0;
 daily_completed integer := 0;
 daily_perfect integer := 0;
 daily_score_total integer := 0;
 daily_streak integer := 0;
 progressive_generated integer := 0;
 generated_specialties integer := 0;
 accuracy_50 integer := 0;
 accuracy_100 integer := 0;
begin
 if uid is null then raise exception 'Authentification requise.'; end if;

 select count(*)::int,
  count(*) filter(where public.practice_case_is_complete(pc))::int,
  count(*) filter(where pc.specialist_opinion_requested)::int,
  count(distinct pc.guard_id)::int,
  coalesce(sum(public.practice_case_xp(pc)),0)::int
 into total_patients,total_complete,total_specialist,total_guards,clinical_xp
 from public.practice_cases pc
 where pc.user_id=uid and pc.encounter_context='emergency_guard'
  and pc.is_draft=false and public.practice_case_is_valid(pc);

 select count(*)::int into standalone_cases
 from public.practice_cases pc
 where pc.user_id=uid and pc.encounter_context='standalone'
  and pc.is_draft=false and public.practice_case_is_valid(pc);

 select count(*)::int,count(*) filter(where qa.is_correct)::int
 into qcm_answered,qcm_correct
 from private.clinical_case_qcm_response_events qa where qa.stats_user_id=uid;

 select count(*)::int,
        count(*) filter(where score=10)::int,
        coalesce(sum(score),0)::int
 into daily_completed,daily_perfect,daily_score_total
 from public.practice_daily_attempts da
 where da.user_id=uid and da.completed_at is not null;

 select coalesce(max(streak_length),0)::int into daily_streak
 from (
   select max(day) as last_day, count(*) as streak_length
   from (
     select day,day-row_number() over(order by day)::int as series
     from (
       select distinct da.challenge_date as day
       from public.practice_daily_attempts da
       where da.user_id=uid and da.completed_at is not null
     ) days
   ) groups_of_days
   group by series
 ) runs
 where runs.last_day >= (now() at time zone 'Africa/Casablanca')::date - 1;

 select count(*)::int,count(distinct specialty)::int
 into progressive_generated,generated_specialties
 from public.practice_generated_cases gc
 where gc.owner_id=uid and gc.generation_status='ready';

 current_streak:=public.practice_current_streak(uid);
 combined_xp:=clinical_xp+qcm_answered*2+qcm_correct*3;
 accuracy_50:=case when qcm_answered>=50
  then floor(qcm_correct::numeric*100/greatest(qcm_answered,1))::int else 0 end;
 accuracy_100:=case when qcm_answered>=100
  then floor(qcm_correct::numeric*100/greatest(qcm_answered,1))::int else 0 end;

 for a in select * from public.practice_achievements loop
   progress_value:=case a.metric
     when 'patients' then total_patients
     when 'complete' then total_complete
     when 'specialist' then total_specialist
     when 'guards' then total_guards
     when 'streak' then current_streak
     when 'qcm_answered' then qcm_answered
     when 'qcm_correct' then qcm_correct
     when 'xp' then combined_xp
     when 'standalone_cases' then standalone_cases
     when 'daily_completed' then daily_completed
     when 'daily_perfect' then daily_perfect
     when 'daily_score_total' then daily_score_total
     when 'daily_streak' then daily_streak
     when 'progressive_generated' then progressive_generated
     when 'generated_specialties' then generated_specialties
     when 'qcm_accuracy_50' then accuracy_50
     when 'qcm_accuracy_100' then accuracy_100
     else 0 end;
   insert into public.user_practice_achievements(
    user_id,achievement_id,progress,unlocked_at,updated_at
   ) values (
    uid,a.id,progress_value,
    case when progress_value>=a.threshold then now() else null end,
    now()
   )
   on conflict(user_id,achievement_id) do update
   set progress=excluded.progress,
       unlocked_at=coalesce(public.user_practice_achievements.unlocked_at,excluded.unlocked_at),
       updated_at=now();
 end loop;
end;
$$;

comment on function public.practice_refresh_my_achievements() is
 'Recompute real achievements from scoped persisted user activities; preserve historic unlock timestamps.';
