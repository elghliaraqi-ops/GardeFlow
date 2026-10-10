-- Isolated Practice glossary cache. Existing case and QCM data are untouched.
create table if not exists public.practice_context_glossary_cache (
  content_hash text primary key,
  status text not null default 'pending' check (status in ('pending', 'ready', 'error')),
  terms jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists practice_context_glossary_created_at_idx
  on public.practice_context_glossary_cache(created_at);
alter table public.practice_context_glossary_cache enable row level security;
revoke all on public.practice_context_glossary_cache from anon, authenticated;
grant select, insert, update on public.practice_context_glossary_cache to service_role;

-- Atomic free-tier budget: no more than 15 distinct Gemini generation
-- attempts per UTC day, even if requests arrive concurrently.
create or replace function public.practice_glossary_limit()
returns trigger language plpgsql as $$
begin
  perform pg_advisory_xact_lock(919101026);
  if (select count(*) from public.practice_context_glossary_cache
      where created_at >= date_trunc('day', now())) >= 15 then
    raise exception 'practice_glossary_daily_budget_exhausted';
  end if;
  return new;
end;
$$;
revoke all on function public.practice_glossary_limit() from public, anon, authenticated;
drop trigger if exists trg_practice_glossary_limit
  on public.practice_context_glossary_cache;
create trigger trg_practice_glossary_limit
before insert on public.practice_context_glossary_cache
for each row execute function public.practice_glossary_limit();
