-- GardeFlow - sources automatiques des programmes du bloc.
-- Aucun contenu de document n'est lu ni analysé.
-- Cette table sert uniquement à authentifier une source mail (Gmail/Outlook)
-- et à l'associer à un établissement.

create table if not exists public.bloc_mail_sources (
  id uuid primary key default gen_random_uuid(),
  hospital text not null,
  provider text not null,
  source_name text not null,
  label_name text,
  token_hash text not null,
  enabled boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint bloc_mail_sources_provider_check
    check (provider in ('gmail', 'outlook')),
  constraint bloc_mail_sources_hospital_check
    check (hospital in (
      'Hôpital Universitaire International Mohammed VI de Bouskoura',
      'Hôpital Universitaire International Mohammed VI de Rabat',
      'Hôpital Universitaire International Cheikh Khalifa de Casablanca'
    ))
);

create index if not exists bloc_mail_sources_enabled_idx
  on public.bloc_mail_sources(enabled, provider, hospital);

alter table public.bloc_mail_sources enable row level security;

-- Les jetons des sources mail ne doivent jamais être exposés au client Flutter.
revoke all on table public.bloc_mail_sources from anon, authenticated;
