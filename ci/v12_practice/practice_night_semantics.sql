-- Practice guard-date semantics.
-- Day and 24H tiles use their start date.
-- A Nuit tile uses the morning/end date from the official roster:
-- example tile 2026-09-30 Nuit = 2026-09-29 20:00 -> 2026-09-30 08:00.
-- Disciplinary emergency guards remain intentionally included: no is_disciplinary
-- exclusion is applied to Practice streaks, XP, achievements, stats or leaderboard.

create or replace function public.practice_current_streak(p_user_id uuid default auth.uid())
returns integer
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare
  rec record;
  streak integer := 0;
  local_now timestamp := now() at time zone 'Africa/Casablanca';
  guard_end timestamp;
  has_case boolean;
begin
  if p_user_id is null then return 0; end if;
  if auth.uid() is not null and p_user_id <> auth.uid() then
    raise exception 'Practice: accès refusé.';
  end if;

  for rec in
    select pe.id, pe.date_str, pe.shift_id
    from public.planning_entries pe
    where pe.owner_id = p_user_id
      and pe.deleted_at is null
      and pe.shift_id in ('urg-jour','urg-nuit','urg-24h')
    order by pe.date_str desc,
      case pe.shift_id when 'urg-jour' then 1 when 'urg-nuit' then 2 else 3 end desc
  loop
    guard_end := case rec.shift_id
      when 'urg-jour' then rec.date_str::timestamp + interval '20 hours'
      when 'urg-nuit' then rec.date_str::timestamp + interval '8 hours'
      else rec.date_str::timestamp + interval '1 day 8 hours'
    end;

    select exists(
      select 1
      from public.practice_cases pc
      where pc.user_id = p_user_id
        and pc.guard_id = rec.id
        and pc.is_draft = false
        and public.practice_case_is_valid(pc)
    ) into has_case;

    if guard_end > local_now and not has_case then continue; end if;
    if has_case then
      streak := streak + 1;
    elsif guard_end <= local_now then
      exit;
    end if;
  end loop;

  return streak;
end;
$function$;
