-- GardeFlow v11.6.70
-- Workflow sécurisé d'analyse et validation des photos d'astreintes séniors.
-- Les résultats d'analyse restent en brouillon jusqu'à validation explicite d'un admin.

create table if not exists public.senior_oncall_imports (
  id uuid primary key default gen_random_uuid(),
  resource_id uuid not null unique references public.shared_resources(id) on delete cascade,
  hospital text not null,
  status text not null default 'draft'
    check (status in ('draft','published','error')),
  detected_service text,
  detected_month integer check (detected_month is null or detected_month between 1 and 12),
  detected_year integer check (detected_year is null or detected_year between 2020 and 2100),
  confidence numeric(4,3) check (confidence is null or (confidence >= 0 and confidence <= 1)),
  analysis_engine text,
  draft_rows jsonb not null default '[]'::jsonb,
  warnings jsonb not null default '[]'::jsonb,
  raw_text text,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  published_at timestamptz
);

create index if not exists senior_oncall_imports_hospital_status_idx
  on public.senior_oncall_imports(hospital, status, updated_at desc);

create index if not exists senior_oncall_imports_created_by_idx
  on public.senior_oncall_imports(created_by);

alter table public.senior_oncall_imports enable row level security;

drop policy if exists senior_oncall_imports_admin_read on public.senior_oncall_imports;
create policy senior_oncall_imports_admin_read
on public.senior_oncall_imports
for select
to authenticated
using ((select public.is_admin()));

drop policy if exists senior_oncall_imports_admin_insert on public.senior_oncall_imports;
create policy senior_oncall_imports_admin_insert
on public.senior_oncall_imports
for insert
to authenticated
with check ((select public.is_admin()) and created_by = (select auth.uid()));

drop policy if exists senior_oncall_imports_admin_update on public.senior_oncall_imports;
create policy senior_oncall_imports_admin_update
on public.senior_oncall_imports
for update
to authenticated
using ((select public.is_admin()))
with check ((select public.is_admin()) and created_by = (select auth.uid()));

drop policy if exists senior_oncall_imports_admin_delete on public.senior_oncall_imports;
create policy senior_oncall_imports_admin_delete
on public.senior_oncall_imports
for delete
to authenticated
using ((select public.is_admin()));

grant select, insert, update, delete
on public.senior_oncall_imports
to authenticated;

create or replace function public.publish_senior_oncall_import(
  p_import_id uuid,
  p_rows jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_import public.senior_oncall_imports%rowtype;
  v_row jsonb;
  v_name text;
  v_service text;
  v_phone text;
  v_phone_digits text;
  v_phone_norm text;
  v_dates date[];
  v_source text;
  v_roster_count integer := 0;
  v_contact_count integer := 0;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'admin_required';
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'invalid_rows';
  end if;

  select *
    into v_import
  from public.senior_oncall_imports
  where id = p_import_id
  for update;

  if not found then
    raise exception 'import_not_found';
  end if;

  if v_import.created_by <> auth.uid() then
    raise exception 'import_owner_mismatch';
  end if;

  v_source := 'photo:' || v_import.resource_id::text;

  delete from public.senior_oncall_rosters
  where source_label = v_source;

  for v_row in select value from jsonb_array_elements(p_rows)
  loop
    v_name := btrim(coalesce(v_row->>'name',''));
    v_service := btrim(coalesce(v_row->>'service',''));
    v_phone := btrim(coalesce(v_row->>'phone',''));

    if v_name = '' or v_service = '' then
      continue;
    end if;

    select coalesce(array_agg(distinct d order by d), '{}'::date[])
      into v_dates
    from (
      select nullif(btrim(x), '')::date as d
      from jsonb_array_elements_text(coalesce(v_row->'dates','[]'::jsonb)) as t(x)
      where nullif(btrim(x), '') is not null
    ) q
    where d is not null;

    if cardinality(v_dates) = 0 then
      continue;
    end if;

    if v_phone <> '' then
      v_phone_digits := regexp_replace(v_phone, '[^0-9+]', '', 'g');
      if v_phone_digits like '00%' then
        v_phone_norm := '+' || substr(v_phone_digits, 3);
      elsif v_phone_digits like '+%' then
        v_phone_norm := v_phone_digits;
      elsif v_phone_digits like '0%' and length(regexp_replace(v_phone_digits, '[^0-9]', '', 'g')) = 10 then
        v_phone_norm := '+212' || substr(regexp_replace(v_phone_digits, '[^0-9]', '', 'g'), 2);
      elsif v_phone_digits like '212%' then
        v_phone_norm := '+' || v_phone_digits;
      else
        v_phone_norm := v_phone;
      end if;
    else
      v_phone_norm := null;
    end if;

    insert into public.senior_oncall_rosters(
      hospital, service, senior_name, senior_phone, duty_dates, source_label, updated_at
    )
    values (
      v_import.hospital, v_service, v_name, v_phone_norm, v_dates, v_source, now()
    )
    on conflict (hospital, service, senior_name, source_label)
    do update set
      senior_phone = excluded.senior_phone,
      duty_dates = excluded.duty_dates,
      updated_at = now();

    v_roster_count := v_roster_count + 1;

    if v_phone_norm is not null and btrim(v_phone_norm) <> '' then
      if not exists (
        select 1 from public.directory_contacts dc
        where dc.hospital = v_import.hospital
          and dc.phone = v_phone_norm
      ) then
        insert into public.directory_contacts(
          category, name, phone, hospital, service, created_by
        )
        values (
          'medecins-seniors', v_name, v_phone_norm, v_import.hospital,
          case
            when v_service like 'USIP — %' then 'USIP'
            when v_service like 'Réanimation adulte — %' then 'Réanimation adulte'
            when v_service like 'Réanimation pédiatrique%' then 'Réanimation pédiatrique'
            else v_service
          end,
          auth.uid()
        );
        v_contact_count := v_contact_count + 1;
      end if;
    end if;
  end loop;

  update public.senior_oncall_imports
  set status = 'published',
      draft_rows = p_rows,
      published_at = now(),
      updated_at = now()
  where id = p_import_id;

  return jsonb_build_object(
    'ok', true,
    'roster_rows', v_roster_count,
    'directory_contacts_added', v_contact_count,
    'source_label', v_source
  );
end;
$$;

revoke all on function public.publish_senior_oncall_import(uuid,jsonb)
  from public, anon;
grant execute on function public.publish_senior_oncall_import(uuid,jsonb)
  to authenticated;
