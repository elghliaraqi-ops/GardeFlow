-- GardeFlow Practice — migration vers les QCM « cours + recommandations ».
-- Les anciennes questions IA restent utilisables comme fallbacks jusqu'à ce que
-- le feed déclenche leur régénération par la nouvelle Edge Function avec recherche web.
-- Aucune réponse n'est supprimée ici : l'invalidation n'intervient qu'au moment
-- où un nouveau jeu de questions est effectivement généré pour le cas concerné.

begin;

update public.clinical_case_qcms
set generation_source = 'fallback',
    updated_at = now()
where generation_source = 'openai';

commit;
