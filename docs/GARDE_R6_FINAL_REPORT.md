# GardeFlow — Rapport de verrouillage fonctionnel du module Garde R6

**État : PRÉ-DÉPLOIEMENT — branche validée côté Flutter, non déployée en production**

- Branche : `garde-functional-lock-r6-20261007`
- PR : #79 (brouillon)
- Baseline avant modification : `824ea9ea3f8a75a9353481b9bf2ab155faa97968`
- Révision moteur cible : `v12.0.2-r6`
- Production Supabase : **inchangée**
- `main` : **non fusionnée**

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
- Page + zone conservées pour les conflits.
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

## 6. Migration base de données

Migration additive uniquement :

`supabase/migrations/20261007231000_garde_functional_lock_r6.sql`

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

Dernier CI de la branche :

- **59 tests passés**
- `flutter test` : succès
- compilation des tests : succès
- `flutter analyze lib test --no-fatal-infos --no-fatal-warnings` exécuté ;
  le dépôt possède des warnings/info historiques, mais aucune erreur fatale n'a bloqué le pipeline.

### Tests R6 ajoutés

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

### Tests métier historiques existants repassés

- même hôpital ;
- même service pour Service ;
- promotion Urgences ;
- protections et écrans mobiles concernés ;
- tests Practice / autres modules existants : suite verte.

### Garde-fous GitHub

- GardeFlow hardening guardrails : succès
- Supabase hardening checks : succès
- GardeFlow hardening CI : succès

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

Le travail n'est pas déclaré “fonctionnellement verrouillé en production” tant que les étapes suivantes ne sont pas terminées :

1. appliquer la migration R6 dans un environnement Supabase de validation ou, à défaut, dans une fenêtre de déploiement contrôlée ;
2. déployer l'Edge Function R6 ;
3. exécuter au moins les cinq anciens PDF privés ci-dessus avec le vrai pipeline R6 ;
4. établir pour chacun un golden result exact ;
5. exiger :
   - 0 garde manquante ;
   - 0 garde supplémentaire ;
   - 0 mauvaise attribution ;
   - 0 mauvaise date ;
   - 0 confusion Jour/Nuit/24H ;
   - 0 confusion Service/Urgences ;
6. tester les RPC de recalcul et les RLS avec une session admin réelle ;
7. seulement ensuite fusionner la PR et déployer.

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

Motif : le code Flutter est vert et les garde-fous sont verts, mais la migration/Edge Function R6 et le corpus historique réel doivent encore être validés ensemble avant de toucher à la production.

C'est un blocage volontaire conforme au principe fail-closed demandé.
