# GardeFlow — Rapport de verrouillage fonctionnel du module Garde R6

**État : PRÉ-DÉPLOIEMENT — Flutter + SQL/RPC + Edge Function validés en environnement isolé, non déployés en production**

- Branche : `garde-functional-lock-r6-20261007`
- PR : #79 (brouillon)
- Baseline avant modification : `824ea9ea3f8a75a9353481b9bf2ab155faa97968`
- Révision moteur cible : `v12.0.2-r6`
- Production Supabase : **inchangée**
- `main` : **non fusionnée**

## Périmètre fonctionnel R6 — Urgences uniquement

R6 traite exclusivement les plannings officiels des **Urgences**.

Créneaux autorisés :

- `urg-jour`
- `urg-nuit`
- `urg-24h`

Les plannings de **Service** ne passent pas par ce moteur et ne doivent pas être interprétés, importés, recalculés ou fusionnés par R6. Toute valeur `service-*` présentée au pipeline R6 doit être refusée explicitement.

Cette séparation est volontaire afin de préserver les règles historiques du module Service et d'éviter toute modification implicite de son fonctionnement.

## 1. Fonctionnalités existantes recensées avant modification

L'inventaire exhaustif est figé dans `docs/GARDE_FUNCTIONAL_LOCK_MATRIX.md`.

Les fonctions historiques conservées couvrent notamment :

- console admin historique et calendrier individuel ;
- validation/refus/réouverture des mois ;
- validation et gestion des comptes ;
- réinitialisation mot de passe / suppression compte ;
- notifications, alertes, transferts, échanges et congés ;
- règles même hôpital / même service / promotion Urgences ;
- protections des gardes disciplinaires ;
- attribution manuelle disciplinaire ;
- consultation, recherche, upload et suppression des PDF officiels ;
- historique/version active des plannings officiels ;
- protections R4 : versions immuables, anti-downgrade, couverture fail-closed, continuité et protection des dates ;
- synchronisation et superposition personnelle ;
- journal administratif ;
- paramètres, rappels, alarmes, realtime planning ;
- écrans hors périmètre Garde (Astreintes, Practice, annuaire) laissés intacts.

## 2. Ce qui a été déplacé dans la nouvelle console

Une nouvelle console modulaire devient le point d'entrée principal administrateur.

Sections :

1. Tableau de bord
2. Médecins et utilisateurs
3. Plannings officiels
4. Lecture PDF / Import
5. Calendriers et superpositions
6. Échanges / transferts / demandes
7. Validations et notifications
8. Gardes disciplinaires
9. Logs et traçabilité
10. Paramètres et maintenance

L'ancien `AdminScreen` n'est pas supprimé : il reste accessible comme module historique de compatibilité et comme filet de non-régression.

## 3. Ce qui a été réorganisé

- Les accès admin dispersés dans Profil / Vue Admin / Notifications / Planning officiel / Audit sont regroupés dans une console unique.
- Les fonctions de lecture PDF sont séparées des fonctions d'identification des comptes.
- Les gardes officielles deviennent une source distincte de la couche personnelle `planning_entries`.
- La vérification d'import se concentre sur les anomalies, scores faibles, médecins non inscrits, homonymes et arbitrages.
- Le recalcul des superpositions devient un flux dédié avec aperçu avant application.

## 4. Ce qui a été ajouté

### Moteur de lecture R6

- Lecture A indépendante :
  - géométrie locale PDF lorsqu'elle est exploitable ;
  - fallback visuel A distinct pour un PDF scanné.
- Lecture B visuelle indépendante, sans liste de comptes GardeFlow.
- Lecture C conditionnelle uniquement en cas de désaccord A/B ou de contrôle incomplet.
- Statuts :
  - VERT : A/B concordants + contrôles complets ;
  - ORANGE : C arbitre ou correction humaine ciblée + contrôles complets ;
  - ROUGE : publication automatique bloquée.
- Correction ciblée des seules cellules litigieuses en ROUGE.
- Revalidation structurelle complète après correction humaine.
- Score de confiance par médecin/garde.
- Page + zone conservées pour les conflits et les corrections ciblées.
- Contrôle de plage structurelle explicite : `coverage_start`, `coverage_end`, `coverage_mode`.
- Un planning `full_month` doit contenir tous les jours du mois principal.
- Un planning partiel/multi-mois peut déclarer une `explicit_range`, mais toutes les dates de cette plage doivent être présentes.
- Détection des cellules visuelles dupliquées.
- Page et zone obligatoires pour une lecture visuelle considérée fiable.
- Une divergence A/B/C sur la plage officielle devient une anomalie structurelle non contournable par une simple correction de nom.
- Le moteur ne dépend plus de la base utilisateurs pour reconstruire le document.

### Identité médecin

- prénom et nom séparés obligatoires en R6 ;
- normalisation typographique prudente ;
- aucun auto-matching sur prénom seul, nom seul ou initiales ;
- exact prénom + nom requis pour auto-association ;
- homonymie = ambiguë ;
- fuzzy = suggestion uniquement ;
- médecin non inscrit conservé dans la source officielle ;
- liaison persistante identité planning ↔ compte ;
- suppression/modification tracées ;
- suggestion dynamique lorsqu'un nouveau compte ressemble à une identité historique.

### Superpositions

- aperçu individuel ;
- aperçu global ;
- ajout / modification / retrait / inchangé / conflit ;
- jeton d'aperçu anti-TOCTOU ;
- confirmation explicite avant application ;
- réutilisation des protections R4/R5 existantes ;
- source officielle jamais modifiée ;
- échec de recalcul : sous-transaction annulée, état dérivé restauré, erreur tracée.

## 5. Fichiers et composants modifiés

- `docs/GARDE_FUNCTIONAL_LOCK_MATRIX.md`
- `docs/GARDE_R6_FINAL_REPORT.md`
- `source/lib/models/official_roster_guard.dart`
- `source/lib/screens/admin_console_screen.dart`
- `source/lib/screens/admin_official_roster_review_screen.dart`
- `source/lib/screens/admin_roster_recalculation_screen.dart`
- `source/lib/screens/home_screen.dart`
- `source/lib/screens/profile_screen.dart`
- `source/lib/screens/official_planning_screen.dart`
- `source/lib/services/official_roster_consensus_service.dart`
- `source/lib/services/official_roster_identity_service.dart`
- `source/lib/services/official_roster_import_service.dart`
- `source/lib/services/official_roster_verified_read_service.dart`
- `source/lib/services/supabase_backend_service.dart`
- `source/supabase/functions/analyze-official-roster-pdf/index.ts`
- `source/test/admin_console_inventory_test.dart`
- `source/test/official_roster_r6_safety_test.dart`
- `source/test/official_roster_verified_read_test.dart`
- `supabase/migrations/20261007231000_garde_functional_lock_r6.sql`
- `supabase/migrations/20261008060000_garde_r6_preview_date_type_fix.sql`
- `supabase/migrations/20261008061500_garde_r6_rpc_anon_lockdown.sql`
- `supabase/migrations/20261008063000_garde_r6_fk_indexes.sql`
- `supabase/tests/garde_r6_validation_baseline.sql`
- `supabase/tests/garde_r6_integration_assertions.sql`
- `.github/workflows/supabase-hardening-checks.yml`

## 6. Migration base de données

Migration principale additive :

`supabase/migrations/20261007231000_garde_functional_lock_r6.sql`

Hotfixes de validation également additifs :

- `20261008060000_garde_r6_preview_date_type_fix.sql` : conserve `date_str` en type DATE dans l'aperçu de recalcul ;
- `20261008061500_garde_r6_rpc_anon_lockdown.sql` : retire explicitement EXECUTE au rôle `anon` sur les RPC R6 ;
- `20261008063000_garde_r6_fk_indexes.sql` : ajoute les index de couverture des FK signalées par l'advisor Supabase.

Aucune suppression de table historique et aucune modification destructive prévue.

## 7. Nouvelles tables / données

- `official_roster_import_reports`
- `official_roster_guards`
- `official_roster_identity_links`
- `official_roster_anomalies`
- `official_roster_recalculation_runs`

Les gardes officielles sont stockées indépendamment de `planning_entries`.

## 8. Nouvelles fonctions / services

### Flutter

- `OfficialRosterIdentityService`
- `OfficialRosterConsensusService`
- modèle `OfficialRosterGuard`
- API backend rapports / anomalies / identity links / recalculs.

### SQL / RPC

- `save_official_roster_analysis_r6`
- `admin_set_official_roster_identity_link`
- `admin_delete_official_roster_identity_link`
- `admin_correct_official_roster_guard`
- `admin_preview_official_roster_recalculation`
- `admin_apply_official_roster_recalculation`
- `admin_log_official_roster_global_recalculation`

## 9. Tests réalisés

### CI Flutter

La branche a déjà validé :

- **59 tests Flutter passés** ;
- compilation des tests : succès ;
- `flutter analyze lib test --no-fatal-infos --no-fatal-warnings` exécuté sans erreur fatale ;
- tests de non-régression métier historiques toujours verts.

### Tests R6 Flutter

- normalisation prudente ;
- exact prénom + nom ;
- prénom seul / nom seul refusés ;
- fuzzy suggestion-only ;
- homonymes bloqués ;
- médecin non inscrit conservé ;
- multi-médecins dans une cellule ;
- Jour + Nuit → 24H pour le même médecin ;
- A=B complet → VERT ;
- désaccord A/B → C requis ;
- C arbitre → ORANGE ;
- désaccord persistant → ROUGE ;
- A/B identiques mais structure incomplète → échec ;
- confiance faible → publication bloquée ;
- inventaire de la nouvelle console ;
- maintien des points d'entrée historiques.

### Validation Supabase isolée réelle

Un projet Supabase séparé, sans données de production, a été créé exclusivement pour R6.

Résultats obtenus :

- migration R6 principale appliquée avec succès ;
- hotfix DATE appliqué avec succès ;
- hotfix ACL `anon` appliqué avec succès ;
- index FK appliqués avec succès ;
- Edge Function R6 bundlée et déployée avec `verify_jwt=true` ;
- RLS testée avec session admin et session médecin non-admin ;
- un non-admin voit 0 ligne dans les cinq tables R6 administratives ;
- les sept RPC R6 admin ont `anon_execute=false` ;
- import synthétique : 3 gardes sur 3 conservées, dont inscrit + non inscrit + ambigu ;
- rattachement ultérieur d'un médecin non inscrit à un nouveau compte validé ;
- suppression de liaison validée et auditée ;
- correction ciblée d'une garde validée et auditée ;
- recalcul individuel avec aperçu validé ;
- second aperçu après recalcul = garde inchangée ;
- hash de la source officielle identique avant/après recalcul ;
- journal de recalcul global validé ;
- statut ROUGE refusé ;
- confiance 0,89 refusée ;
- utilisateur non-admin refusé sur RPC admin ;
- jeton d'aperçu périmé/refusé.

### Tests PostgreSQL reproductibles dans GitHub Actions

Le workflow Supabase lance désormais un PostgreSQL 16 éphémère et :

1. construit un socle synthétique R4/R5 ;
2. applique les vraies migrations R6 du dépôt ;
3. exécute les assertions d'import, RLS/ACL, fail-closed et recalcul ;
4. vérifie que la source officielle n'est pas modifiée.

Ce job d'intégration DB a déjà été exécuté avec succès.

### Défauts détectés avant production grâce à cette validation

1. **Type DATE/TEXT dans l'aperçu de recalcul**  
   `g.date_str::text` provoquait une comparaison `date = text`. Corrigé et protégé par CI.

2. **EXECUTE hérité pour le rôle anon**  
   Les RPC refusaient déjà l'action via `is_admin()`, mais `anon` disposait encore du droit SQL d'invocation. Le droit est désormais explicitement retiré et vérifié par CI.

3. **Complétude de bord de planning**  
   La continuité entre première/dernière date ne suffisait pas à prouver que les bords officiels avaient été lus. Les lectures visuelles déclarent désormais leur plage officielle et A/B/C comparent également cette structure.

4. **Index FK R6**  
   Les clés étrangères non couvertes signalées par Supabase ont reçu des index additifs. L'advisor ne signale plus de FK R6 non indexée sur le banc de validation.

### Garde-fous GitHub

- GardeFlow hardening guardrails : succès ;
- Supabase hardening static checks : succès ;
- PostgreSQL R6 integration : succès ;
- GardeFlow hardening CI : succès sur la dernière révision entièrement terminée avant le renforcement de couverture ; chaque nouveau commit relance automatiquement la suite.

## 10. Résultats sur anciens plannings

Plusieurs PDF historiques réels ont été retrouvés dans la bibliothèque privée de l'utilisateur :

- HM6 septembre 2026 ;
- HCK fin août / septembre 2026 ;
- HM6 Rabat septembre 2026 ;
- HM6 juillet / août 2026 ;
- HM6 mars 2026.

Ils contiennent les cas difficiles recherchés :

- cellules fusionnées 24H ;
- plusieurs médecins dans une cellule ;
- noms et prénoms composés ;
- variations de casse / tirets ;
- gardes rouges ;
- cellules vides ;
- périodes chevauchant deux mois.

**Protection de confidentialité : ces PDF ne sont pas copiés dans le dépôt GitHub public.**

À ce stade, ils ont servi à confirmer la couverture fonctionnelle des cas de test, mais ils n'ont pas encore été exécutés de bout en bout par le moteur R6 déployé, puisque R6 n'est volontairement pas déployé en production.

## 11. Points restant à surveiller avant production

La validation infrastructure/backend isolée est maintenant effectuée. Le dernier verrou avant production reste le corpus documentaire réel.

À terminer :

1. fournir/configurer un `OPENAI_API_KEY` dans un environnement de validation autorisé pour exécuter la vraie Edge Function A/B/C ;
2. faire passer au moins les cinq anciens PDF privés par ce pipeline réel ;
3. établir/valider pour chacun un golden result exact ;
4. exiger :
   - 0 garde manquante ;
   - 0 garde supplémentaire ;
   - 0 mauvaise attribution ;
   - 0 mauvaise date ;
   - 0 confusion Jour/Nuit/24H ;
   - aucune garde de Service acceptée par le moteur R6 Urgences ;
5. vérifier que les cas volontairement partiels sont identifiés comme `explicit_range` et que les mois complets sont identifiés comme `full_month` ;
6. seulement après ces résultats, fusionner la PR et appliquer les migrations/Edge Function à la production.

Le projet Supabase de validation ne contient aucune donnée de production et les PDF historiques privés ne sont pas copiés dans le dépôt GitHub public.

## 12. Confirmation de non-suppression

À l'état actuel de la branche :

- aucune fonction historique recensée n'a été supprimée du code ;
- l'ancien `AdminScreen` est conservé ;
- les règles `BusinessRules` n'ont pas été modifiées ;
- les flux d'échanges/transferts/congés n'ont pas été réécrits ;
- les protections R4/R5 restent utilisées par les recalculs ;
- les tests d'inventaire et les tests métier existants passent.

**La confirmation “aucune régression en production” restera volontairement en attente tant que l'étape end-to-end Supabase + anciens PDF n'est pas exécutée.**

---

## Décision de déploiement

**NO-GO production pour l'instant.**

Le code Flutter, les migrations SQL, les RPC, les ACL/RLS, les recalculs et le bundle Edge R6 ont été validés hors production.

Le seul blocage majeur restant est volontaire : exécuter le **vrai moteur visuel OpenAI A/B/C** sur les anciens PDF privés et comparer le résultat à des références exactes avant de fusionner ou déployer.

C'est conforme au principe fail-closed demandé : aucune validation “fonctionnellement verrouillée” n'est déclarée sur la seule base d'une compilation ou de tests synthétiques.
