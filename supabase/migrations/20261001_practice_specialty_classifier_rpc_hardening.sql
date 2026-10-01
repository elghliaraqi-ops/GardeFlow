-- Les fonctions ci-dessous sont des helpers internes au trigger de classement.
-- Elles ne doivent pas être exposées comme RPC publiques via PostgREST.

revoke all on function public.clinical_case_apply_specialty_classification()
from public, anon, authenticated;

revoke all on function public.clinical_case_classify_specialty(
  text,text,text,text,text,text,text,text,text
)
from public, anon, authenticated;

grant execute on function public.clinical_case_classify_specialty(
  text,text,text,text,text,text,text,text,text
)
to service_role;
