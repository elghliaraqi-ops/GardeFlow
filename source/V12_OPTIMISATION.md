# GardeFlow V12

V12 part d'un principe simple : le dossier `source/` est désormais la source applicative de référence.

## Ce qui change

- Tous les correctifs fonctionnels V11.6.x sont intégrés directement dans `source/`.
- Les builds Android, Web et iOS doivent compiler `source/` directement et ne doivent plus reconstruire l'application en rejouant des dizaines de patches historiques.
- La logique métier validée reste inchangée : gardes de service, urgences, échanges, transferts, congés, gardes disciplinaires, validation mensuelle, promotions, astreintes, annuaire, notifications et planning officiel.
- Les protections Supabase/RLS et les correctifs de suppression de comptes sont conservés.
- Les anciens scripts de patch peuvent rester dans le dépôt comme archive historique mais ne sont plus la chaîne de build de production.

## Version

- Version applicative : `12.0.0+300`
- Source canonique : `source/`
- Branche de préparation : `v12-optimisee`
- Sauvegarde du main pré-V12 : `backup-main-pre-v12-20260923`

## Objectifs techniques

1. réduire le temps et la fragilité des builds ;
2. supprimer la dépendance à la reconstruction V11 par empilement de patches ;
3. garder une seule source Flutter lisible et modifiable ;
4. conserver les tests de fumée, l'analyse Flutter et les vérifications de sécurité ;
5. aligner le dépôt sur l'état réellement déployé de Supabase.
