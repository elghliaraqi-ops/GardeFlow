-- GardeFlow V11.6.70
-- Pipeline OCR des photos d'astreinte senior, y compris les photos déjà uploadées.

alter table public.shared_resources
  add column if not exists analysis_status text,
  add column if not exists analysis_message text,
  add column if not exists analyzed_at timestamptz,
  add column if not exists analysis_version text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='shared_resources_analysis_status_check'
      and conrelid='public.shared_resources'::regclass
  ) then
    alter table public.shared_resources
      add constraint shared_resources_analysis_status_check
      check (
        analysis_status is null
        or analysis_status in ('pending','processing','completed','partial','error')
      );
  end if;
end $$;

update public.shared_resources
set analysis_status='pending',
    analysis_message=null,
    analyzed_at=null
where kind='astreinte_photo'
  and analysis_status is null;

create or replace function public.shared_resource_prepare_astreinte_analysis()
returns trigger
language plpgsql
set search_path=public
as $$
begin
  if new.kind='astreinte_photo' then
    if tg_op='INSERT' then
      new.analysis_status := coalesce(new.analysis_status,'pending');
    end if;
    if tg_op='UPDATE'
       and old.storage_path is distinct from new.storage_path then
      new.analysis_status := 'pending';
      new.analysis_message := null;
      new.analyzed_at := null;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists shared_resource_prepare_astreinte_analysis_trg
  on public.shared_resources;
create trigger shared_resource_prepare_astreinte_analysis_trg
before insert or update on public.shared_resources
for each row execute function public.shared_resource_prepare_astreinte_analysis();

create or replace function public.shared_resource_sync_astreinte_service()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.kind='astreinte_photo'
     and old.service is distinct from new.service
     and new.service is not null
     and btrim(new.service)<>'' then
    update public.senior_oncall_assignments
    set service=new.service,
        updated_at=now()
    where source_resource_id=new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists shared_resource_sync_astreinte_service_trg
  on public.shared_resources;
create trigger shared_resource_sync_astreinte_service_trg
after update of service on public.shared_resources
for each row execute function public.shared_resource_sync_astreinte_service();

create or replace function public.replace_senior_oncall_photo_analysis(
  p_resource_id uuid,
  p_assignments jsonb,
  p_inferred_service text default null,
  p_status text default 'completed',
  p_message text default null
)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_resource public.shared_resources%rowtype;
  v_service text;
  v_row jsonb;
  v_count integer := 0;
  v_date date;
  v_name text;
  v_phone text;
  v_conf numeric;
begin
  if auth.uid() is null or not public.current_account_active() or not public.is_admin() then
    raise exception 'forbidden';
  end if;

  if p_status not in ('completed','partial','error') then
    raise exception 'invalid_status';
  end if;

  select * into v_resource
  from public.shared_resources
  where id=p_resource_id
    and kind='astreinte_photo'
  for update;

  if not found then
    raise exception 'resource_not_found';
  end if;

  v_service := nullif(btrim(v_resource.service),'');
  if (v_service is null or lower(v_service)=lower('À classer'))
     and nullif(btrim(p_inferred_service),'') is not null then
    v_service := btrim(p_inferred_service);
    update public.shared_resources
    set service=v_service
    where id=v_resource.id;
  end if;
  v_service := coalesce(v_service,'À classer');

  delete from public.senior_oncall_assignments
  where source_resource_id=v_resource.id;

  if p_assignments is not null and jsonb_typeof(p_assignments)='array' then
    for v_row in select value from jsonb_array_elements(p_assignments)
    loop
      begin
        v_date := nullif(v_row->>'date','')::date;
      exception when others then
        v_date := null;
      end;
      v_name := nullif(btrim(v_row->>'name'),'');
      v_phone := nullif(btrim(v_row->>'phone'),'');
      begin
        v_conf := nullif(v_row->>'confidence','')::numeric;
      exception when others then
        v_conf := null;
      end;

      if v_date is not null and v_name is not null then
        insert into public.senior_oncall_assignments(
          hospital,
          service,
          duty_date,
          senior_name,
          senior_phone,
          source_resource_id,
          source_updated_at,
          confidence,
          validation_status,
          validated_by,
          validated_at
        ) values (
          v_resource.hospital,
          v_service,
          v_date,
          v_name,
          v_phone,
          v_resource.id,
          v_resource.updated_at,
          v_conf,
          'validated',
          auth.uid(),
          now()
        )
        on conflict do nothing;
        v_count := v_count + 1;
      end if;
    end loop;
  end if;

  update public.shared_resources
  set analysis_status=p_status,
      analysis_message=p_message,
      analyzed_at=now(),
      analysis_version='mlkit-v1'
  where id=v_resource.id;

  return v_count;
end;
$$;

revoke all on function public.replace_senior_oncall_photo_analysis(uuid,jsonb,text,text,text)
  from public, anon;
grant execute on function public.replace_senior_oncall_photo_analysis(uuid,jsonb,text,text,text)
  to authenticated;
