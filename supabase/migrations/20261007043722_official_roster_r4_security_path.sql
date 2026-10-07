create or replace function public.guardeflow_roster_revision_rank(p_revision text)
returns integer
language sql
immutable
set search_path to 'public'
as $function$
  select coalesce(
    nullif((regexp_match(coalesce(p_revision,''), 'r([0-9]+)$'))[1], '')::int,
    0
  );
$function$;
