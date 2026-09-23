-- GardeFlow v11.6.70
-- Ajout rapide d'un numéro depuis le calendrier Astreintes Séniors.
-- Le numéro est synchronisé dans l'annuaire et sur toutes les lignes d'astreinte
-- du même médecin dans le même établissement.

create or replace function public.add_senior_oncall_contact(
  p_name text,
  p_phone text,
  p_hospital text,
  p_service text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_name text := btrim(coalesce(p_name, ''));
  v_service text := nullif(btrim(coalesce(p_service, '')), '');
  v_phone_raw text := btrim(coalesce(p_phone, ''));
  v_digits text;
  v_phone text;
  v_existing uuid;
  v_roster_count integer := 0;
  v_contact_added boolean := false;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'admin_required';
  end if;
  if v_name = '' then raise exception 'invalid_name'; end if;
  if btrim(coalesce(p_hospital, '')) = '' then raise exception 'invalid_hospital'; end if;

  v_digits := regexp_replace(v_phone_raw, '[^0-9+]', '', 'g');
  if v_digits like '00%' then
    v_phone := '+' || substr(v_digits, 3);
  elsif v_digits like '+%' then
    v_phone := v_digits;
  elsif v_digits like '0%' and length(regexp_replace(v_digits, '[^0-9]', '', 'g')) = 10 then
    v_phone := '+212' || substr(regexp_replace(v_digits, '[^0-9]', '', 'g'), 2);
  elsif v_digits like '212%' then
    v_phone := '+' || v_digits;
  else
    v_phone := v_phone_raw;
  end if;

  if length(regexp_replace(v_phone, '[^0-9]', '', 'g')) < 9 then
    raise exception 'invalid_phone';
  end if;

  select id into v_existing
  from public.directory_contacts
  where hospital = p_hospital
    and category = 'medecins-seniors'
    and lower(btrim(name)) = lower(v_name)
  order by created_at
  limit 1;

  if v_existing is not null then
    update public.directory_contacts
    set phone = v_phone,
        service = coalesce(v_service, service),
        updated_at = now()
    where id = v_existing;
  elsif not exists (
    select 1 from public.directory_contacts
    where hospital = p_hospital and phone = v_phone
  ) then
    insert into public.directory_contacts(category, name, phone, hospital, service, created_by)
    values ('medecins-seniors', v_name, v_phone, p_hospital, v_service, auth.uid());
    v_contact_added := true;
  end if;

  update public.senior_oncall_rosters
  set senior_phone = v_phone,
      updated_at = now()
  where hospital = p_hospital
    and lower(btrim(senior_name)) = lower(v_name);
  get diagnostics v_roster_count = row_count;

  return jsonb_build_object(
    'ok', true,
    'phone', v_phone,
    'roster_rows_updated', v_roster_count,
    'directory_contact_added', v_contact_added
  );
end;
$$;

revoke all on function public.add_senior_oncall_contact(text,text,text,text) from public, anon;
grant execute on function public.add_senior_oncall_contact(text,text,text,text) to authenticated;
