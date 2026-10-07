create table if not exists public.official_roster_preflight_reads (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  slot text not null,
  file_sha256 text not null,
  extraction jsonb not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 minutes'),
  check (slot in ('hm6_bouskoura','hm6_rabat','hck_casa')),
  check (file_sha256 ~ '^[0-9a-f]{64}$')
);

create index if not exists official_roster_preflight_reads_expiry_idx
  on public.official_roster_preflight_reads(expires_at);

alter table public.official_roster_preflight_reads enable row level security;

drop policy if exists official_roster_preflight_reads_deny_direct
on public.official_roster_preflight_reads;

create policy official_roster_preflight_reads_deny_direct
on public.official_roster_preflight_reads
as restrictive
for all
to authenticated
using (false)
with check (false);

revoke all on public.official_roster_preflight_reads
from public, anon, authenticated;
