-- GardeFlow V12 — Actualités indépendantes de l'API Instagram
-- Déjà appliqué sur PlanningHM6 le 26/09/2026.
-- Les lecteurs gardent SELECT; les écritures passent uniquement par des RPC admin.

revoke insert, update, delete, truncate on table public.daily_news_posts from anon, authenticated;
grant select on table public.daily_news_posts to anon, authenticated;

create or replace function public.admin_publish_daily_news(
  p_source_key text,
  p_display_name text,
  p_caption text,
  p_permalink text,
  p_media_url text default null,
  p_posted_at timestamptz default now()
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_external_id text;
  v_source_key text := lower(trim(coalesce(p_source_key, '')));
  v_display_name text := nullif(trim(coalesce(p_display_name, '')), '');
  v_username text;
  v_known_name text;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;

  if v_source_key not in ('ami_um6','um6ss','huim6_bouskoura','huim6_rabat','hck','other') then
    raise exception 'invalid_source_key';
  end if;

  if nullif(trim(coalesce(p_caption, '')), '') is null then
    raise exception 'caption_required';
  end if;

  if nullif(trim(coalesce(p_permalink, '')), '') is null
     or trim(p_permalink) !~* '^https?://' then
    raise exception 'valid_permalink_required';
  end if;

  if nullif(trim(coalesce(p_media_url, '')), '') is not null
     and trim(p_media_url) !~* '^https?://' then
    raise exception 'valid_media_url_required';
  end if;

  if v_source_key <> 'other' then
    select s.username, s.display_name
      into v_username, v_known_name
    from public.daily_news_sources s
    where s.source_key = v_source_key
    limit 1;
  end if;

  v_username := coalesce(v_username, case when v_source_key = 'other' then 'gardeflow' else v_source_key end);
  v_display_name := coalesce(v_display_name, v_known_name, 'Actualité GardeFlow');
  v_external_id := 'manual-' || gen_random_uuid()::text;

  insert into public.daily_news_posts (
    external_id,
    source_key,
    username,
    display_name,
    caption,
    media_type,
    media_url,
    cached_media_url,
    thumbnail_url,
    permalink,
    posted_at,
    synced_at
  ) values (
    v_external_id,
    v_source_key,
    v_username,
    v_display_name,
    trim(p_caption),
    'MANUAL',
    nullif(trim(coalesce(p_media_url, '')), ''),
    null,
    null,
    trim(p_permalink),
    coalesce(p_posted_at, now()),
    now()
  );

  return v_external_id;
end;
$$;

revoke all on function public.admin_publish_daily_news(text,text,text,text,text,timestamptz) from public, anon;
grant execute on function public.admin_publish_daily_news(text,text,text,text,text,timestamptz) to authenticated;

create or replace function public.admin_delete_daily_news(p_external_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;

  if coalesce(p_external_id, '') !~ '^manual-' then
    raise exception 'only_manual_news_can_be_deleted';
  end if;

  delete from public.daily_news_posts
  where external_id = p_external_id;
end;
$$;

revoke all on function public.admin_delete_daily_news(text) from public, anon;
grant execute on function public.admin_delete_daily_news(text) to authenticated;
