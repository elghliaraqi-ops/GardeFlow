-- GardeFlow V11.6.69 - stable push device registration
alter table public.push_tokens
  add column if not exists device_id text;

create unique index if not exists push_tokens_owner_device_uidx
  on public.push_tokens(owner_id,device_id)
  where device_id is not null;

create or replace function public.register_push_device(
  p_token text,
  p_platform text,
  p_device_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  p public.profiles%rowtype;
  v_device_id text := nullif(trim(p_device_id),'');
begin
  select * into p
  from public.profiles
  where id=auth.uid() and account_status='active';

  if not found then raise exception 'Profil actif introuvable'; end if;
  if coalesce(trim(p_token),'')='' then raise exception 'Token push vide'; end if;
  if v_device_id is null then raise exception 'Identifiant appareil vide'; end if;

  -- One current token per app installation. A token rotation replaces the old
  -- token for this device instead of accumulating stale registrations.
  delete from public.push_tokens
  where owner_id=p.id
    and device_id=v_device_id
    and token<>p_token;

  -- Migrate away old registrations that predate stable installation IDs.
  delete from public.push_tokens
  where owner_id=p.id
    and platform=coalesce(nullif(trim(p_platform),''),'web')
    and device_id is null
    and token<>p_token;

  insert into public.push_tokens(
    token,owner_id,owner_phone,platform,device_id,created_at,updated_at
  )
  values(
    p_token,p.id,p.phone,coalesce(nullif(trim(p_platform),''),'web'),
    v_device_id,now(),now()
  )
  on conflict(token)
  do update set
    owner_id=excluded.owner_id,
    owner_phone=excluded.owner_phone,
    platform=excluded.platform,
    device_id=excluded.device_id,
    updated_at=now();

  -- Long-dead legacy tokens are safe to discard.
  delete from public.push_tokens
  where updated_at < now() - interval '60 days';
end;
$$;

revoke all on function public.register_push_device(text,text,text)
  from public, anon;
grant execute on function public.register_push_device(text,text,text)
  to authenticated;
