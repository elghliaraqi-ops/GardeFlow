-- Personal purchased references: server-only retrieval, never a public catalog.
create table if not exists public.practice_emc_documents (
  id text primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  category text not null,
  url text not null,
  content text not null,
  imported_at timestamptz not null default now()
);
alter table public.practice_emc_documents enable row level security;
revoke all on public.practice_emc_documents from public, anon, authenticated;
grant select, insert, update, delete on public.practice_emc_documents to service_role;
create index if not exists practice_emc_documents_owner_idx on public.practice_emc_documents(owner_id);
