-- GardeFlow: permanent fix for individual re-superposition of official rosters.
-- Applies to every current/future official PDF and all supported hospitals.
-- The RPC remains responsible for validating auth, profile, hospital, resource version,
-- ownership and allowed shifts. This trigger prevents direct/non-official writes.

create or replace function public.protect_official_import_integrity()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_official_import boolean := coalesce(current_setting('gardeflow.official_import',true),'0')='1';
  v_allowed boolean := false;
begin
  if not v_official_import then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;

  if public.is_admin() or auth.role()='service_role' then
    if tg_op='DELETE' then return old; else return new; end if;
  end if;

  if auth.uid() is null then raise exception 'Session requise'; end if;
  if tg_op='DELETE' then raise exception 'Une garde issue du planning officiel ne peut pas être supprimée par une synchronisation individuelle'; end if;
  if new.owner_id is distinct from auth.uid() then raise exception 'Une synchronisation individuelle ne peut modifier que votre propre planning'; end if;

  if tg_op='UPDATE' and old.source_type='official_emergency' and old.deleted_at is null and new.deleted_at is not null then
    new.deleted_at := old.deleted_at;
  end if;

  if tg_op='UPDATE'
     and old.source_type='official_emergency'
     and new.source_type='official_emergency'
     and new.owner_id is not distinct from old.owner_id
     and new.date_str is not distinct from old.date_str
     and new.shift_id is not distinct from old.shift_id
     and new.source_resource_id is not distinct from old.source_resource_id then
    return new;
  end if;

  if new.source_type <> 'official_emergency'
     or new.source_resource_id is null
     or new.source_resource_updated_at is null then
    raise exception 'Import officiel individuel invalide';
  end if;

  select exists(
    select 1 from public.official_disciplinary_guards g
    where g.owner_id=new.owner_id
      and g.date_str=new.date_str
      and g.shift_id=new.shift_id
      and g.resource_id=new.source_resource_id
      and g.resource_updated_at=new.source_resource_updated_at
  ) into v_allowed;

  if not v_allowed then
    v_allowed := public.official_unmatched_assignment_matches_profile(
      new.source_resource_id,new.source_resource_updated_at,new.owner_id,new.date_str,new.shift_id
    );
  end if;

  -- A profile re-sync reparses the exact current official PDF. The server RPC has
  -- already validated the authenticated profile, hospital, current resource version,
  -- ownership and shift whitelist. Permit that trusted import even if the doctor's
  -- name was not matched during the original administrator import.
  if not v_allowed then
    v_allowed := exists(
      select 1
      from public.shared_resources r
      join public.profiles p on p.id=new.owner_id
      where r.id=new.source_resource_id
        and r.kind='official_pdf'
        and r.updated_at=new.source_resource_updated_at
        and p.id=auth.uid()
        and p.account_status='active'
        and p.hospital = case r.slot
          when 'hm6_bouskoura' then 'Hôpital Universitaire International Mohammed VI de Bouskoura'
          when 'hm6_rabat' then 'Hôpital Universitaire International Mohammed VI de Rabat'
          when 'hck_casa' then 'Hôpital Universitaire International Cheikh Khalifa de Casablanca'
          else null
        end
    );
  end if;

  if not v_allowed then
    raise exception 'Cette affectation ne correspond pas au planning officiel enregistré par l’administrateur';
  end if;

  return new;
end;
$$;
