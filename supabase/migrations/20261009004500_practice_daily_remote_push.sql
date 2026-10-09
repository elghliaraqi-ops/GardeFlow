-- Remote Practice reminder: secret is generated inside Vault, never in GitHub.
do $vault$
begin
 if not exists(select 1 from vault.secrets where name='practice_daily_dispatch_token') then
   perform vault.create_secret(encode(extensions.gen_random_bytes(32),'hex'),'practice_daily_dispatch_token');
 end if;
end;
$vault$;

create or replace function public.practice_daily_validate_cron(p_token text)
returns boolean language sql stable security definer
set search_path=public,pg_temp
as $$
 select p_token is not null and length(p_token)=64 and exists (
   select 1 from vault.decrypted_secrets v
   where v.name='practice_daily_dispatch_token' and v.decrypted_secret=p_token
 );
$$;

create or replace function public.practice_daily_push_candidates(p_day date)
returns table(user_id uuid)
language sql stable security definer set search_path=public,pg_temp
as $$
 select p.id
 from public.profiles p
 where p.account_status='active'
   and p_day=(now() at time zone 'Africa/Casablanca')::date
   and exists (select 1 from public.push_tokens t where t.owner_id=p.id)
   and coalesce((select pref.enabled from public.practice_daily_reminders pref
     where pref.user_id=p.id),true)
   and not exists(select 1 from public.practice_daily_attempts a
     where a.user_id=p.id and a.challenge_date=p_day)
   and not exists(select 1 from public.practice_push_receipts rec
     where rec.user_id=p.id and rec.kind='practice_daily_challenge'
     and rec.resource_id=p_day::text);
$$;

create or replace function public.practice_daily_claim_push(p_user_id uuid,p_day date)
returns boolean language plpgsql security definer
set search_path=public,pg_temp
as $$
declare v_claimed boolean;
begin
 if p_user_id is null or p_day is distinct from (now() at time zone 'Africa/Casablanca')::date
 or not exists(select 1 from public.profiles p where p.id=p_user_id and p.account_status='active')
 or not exists(select 1 from public.push_tokens t where t.owner_id=p_user_id)
 or coalesce((select r.enabled from public.practice_daily_reminders r where r.user_id=p_user_id),true)=false
 or exists(select 1 from public.practice_daily_attempts a where a.user_id=p_user_id and a.challenge_date=p_day)
 then return false;end if;
 with inserted as (
   insert into public.practice_push_receipts(user_id,kind,resource_id)
   values(p_user_id,'practice_daily_challenge',p_day::text)
   on conflict(user_id,kind,resource_id) do nothing
   returning id
 ) select exists(select 1 from inserted) into v_claimed;
 return coalesce(v_claimed,false);
end;$$;

revoke all on function public.practice_daily_validate_cron(text) from public,anon,authenticated;
revoke all on function public.practice_daily_push_candidates(date) from public,anon,authenticated;
revoke all on function public.practice_daily_claim_push(uuid,date) from public,anon,authenticated;
grant execute on function public.practice_daily_validate_cron(text),
 public.practice_daily_push_candidates(date),
 public.practice_daily_claim_push(uuid,date) to service_role;

-- Supabase pg_cron uses UTC: two candidates ensure 08:00 Casablanca across
-- Morocco's seasonal GMT/GMT+1 changes. The function checks local hour exactly.
select cron.schedule(
 'gardeflow-practice-daily-push',
 '0 7,8 * * *',
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
