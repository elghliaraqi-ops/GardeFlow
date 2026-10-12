-- Daily Practice: retry failed FCM dispatch without duplicating accepted sends.
-- The initial atomic receipt is a reservation, not proof of device delivery.
create or replace function public.practice_daily_release_push(p_user_id uuid,p_day date)
returns boolean language plpgsql security definer
set search_path=public,pg_temp
as $function$
declare v_removed boolean:=false;
begin
  if p_user_id is null or p_day is distinct from (now() at time zone 'Africa/Casablanca')::date
  then return false; end if;
  delete from public.practice_push_receipts
  where user_id=p_user_id and kind='practice_daily_challenge'
    and resource_id=p_day::text
  returning true into v_removed;
  return coalesce(v_removed,false);
end;
$function$;

revoke all on function public.practice_daily_release_push(uuid,date) from public,anon,authenticated;
grant execute on function public.practice_daily_release_push(uuid,date) to service_role;

-- Run every fifteen minutes in both UTC hours spanning 08:00 Casablanca,
-- including Morocco's GMT/Ramadan clock adjustment. The Edge function itself
-- checks the local hour; an accepted FCM dispatch is deduped for the day.
select cron.schedule(
 'gardeflow-practice-daily-push',
 '*/15 7,8 * * *',
 $schedule$
 select net.http_post(
   url:='https://bqmtkdzlqfvfocxlffac.supabase.co/functions/v1/send-practice-daily-reminder',
   headers:=jsonb_build_object('Content-Type','application/json',
     'X-Practice-Cron-Token',(select decrypted_secret from vault.decrypted_secrets
       where name='practice_daily_dispatch_token')),
   body:='{}'::jsonb,
   timeout_milliseconds:=12000
 );
 $schedule$
);
