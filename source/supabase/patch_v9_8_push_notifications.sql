-- HUIM6 Planning V9.8 — appareils FCM / notifications push
-- À exécuter APRÈS le patch V9.7 si votre base est déjà installée.

create table if not exists public.push_tokens (
  token text primary key,
  owner_phone text not null references public.profiles(phone) on update cascade on delete cascade,
  platform text not null default 'web',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists push_tokens_owner_idx on public.push_tokens(owner_phone);
alter table public.push_tokens enable row level security;

-- Les tokens FCM ne sont jamais exposés aux autres utilisateurs via SELECT.
revoke all on public.push_tokens from anon, authenticated;

create or replace function public.register_push_token(p_token text, p_platform text default 'web')
returns void
language plpgsql
security definer set search_path=public
as $$
declare p text;
begin
  p := public.current_phone();
  if p is null then raise exception 'Session absente'; end if;
  if coalesce(trim(p_token),'')='' then raise exception 'Token push vide'; end if;

  insert into public.push_tokens(token,owner_phone,platform,updated_at)
  values (p_token,p,coalesce(nullif(trim(p_platform),''),'web'),now())
  on conflict (token) do update
    set owner_phone=excluded.owner_phone,
        platform=excluded.platform,
        updated_at=now();
end;
$$;

create or replace function public.unregister_push_token(p_token text)
returns void
language plpgsql
security definer set search_path=public
as $$
begin
  delete from public.push_tokens
  where token=p_token and owner_phone=public.current_phone();
end;
$$;

grant execute on function public.register_push_token(text,text) to authenticated;
grant execute on function public.unregister_push_token(text) to authenticated;

-- Les Edge Functions utilisent la service_role, qui contourne RLS pour lire
-- les tokens destinataires. Aucune clé privée Firebase n'est stockée en SQL.
