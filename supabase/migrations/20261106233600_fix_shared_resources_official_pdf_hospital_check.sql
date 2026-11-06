-- Fix PostgreSQL 23514 when publishing a new official GardeFlow roster.
-- The publish_official_roster_version RPC stores the canonical hospital in
-- shared_resources.hospital. Legacy official PDFs have hospital = NULL.
-- Keep both representations valid, but reject mismatched slot/hospital pairs.
ALTER TABLE public.shared_resources
  DROP CONSTRAINT shared_resources_hospital_check;

ALTER TABLE public.shared_resources
  ADD CONSTRAINT shared_resources_hospital_check
  CHECK (
    (
      kind = 'astreinte_photo'
      AND hospital IN (
        'Hôpital Universitaire International Mohammed VI de Bouskoura',
        'Hôpital Universitaire International Mohammed VI de Rabat',
        'Hôpital Universitaire International Cheikh Khalifa de Casablanca'
      )
    )
    OR (
      kind = 'official_pdf'
      AND (
        hospital IS NULL
        OR (slot = 'hm6_bouskoura' AND hospital = 'Hôpital Universitaire International Mohammed VI de Bouskoura')
        OR (slot = 'hm6_rabat' AND hospital = 'Hôpital Universitaire International Mohammed VI de Rabat')
        OR (slot = 'hck_casa' AND hospital = 'Hôpital Universitaire International Cheikh Khalifa de Casablanca')
      )
    )
  );