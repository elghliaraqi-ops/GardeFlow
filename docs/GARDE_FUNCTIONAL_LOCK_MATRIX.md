# GardeFlow — Matrice de contrôle avant verrouillage du module Garde

> **Baseline figée avant modification fonctionnelle**
>
> Branche de travail : `garde-functional-lock-r6-20261007`
>
> Commit de référence : `824ea9ea3f8a75a9353481b9bf2ab155faa97968`
>
> Règle de sortie : **aucune mise en production tant qu'une ligne fonctionnelle n'est pas retrouvée et testée OK**.

## Périmètre R6 confirmé — Urgences uniquement

À la demande du propriétaire du produit, le moteur de lecture officielle R6 traite exclusivement les gardes **Urgences** : `urg-jour`, `urg-nuit`, `urg-24h`.

Les gardes **Service** restent gérées par les fonctionnalités historiques de GardeFlow mais sont **hors du moteur PDF officiel R6**. Toute valeur `service-*` présentée au pipeline R6 doit être refusée explicitement. Cette règle ne modifie pas les règles métier historiques des échanges Service.

## Constat d'architecture baseline

- Source Flutter canonique : `source/`.
- Console historique principale : `source/lib/screens/admin_screen.dart`.
- Les fonctions administrateur sont actuellement réparties entre le profil, la Vue Admin, les notifications, les plannings officiels, les gardes disciplinaires, la gestion des comptes et le journal.
- Moteur officiel courant : `v12.0.2-r5`.
- R4 est déjà présent et doit être conservé : couverture fail-closed, continuité, versions immuables, anti-downgrade/réimport et sécurité du chemin d'import.
- R5 ajoute un contrôle visuel distant et un cache vérifié, mais exécute actuellement A/B/C avec le même chemin et lance C systématiquement.
- La lecture vérifiée est encore transformée trop tôt en affectations `profile_id`, ce qui empêche de représenter proprement un médecin non inscrit comme une identité officielle autonome.
- `planning_entries` distingue déjà les entrées dérivées avec `source_type = official_emergency`, `source_resource_id` et `source_resource_updated_at`. Cette séparation doit être conservée pour que les recalculs n'altèrent jamais la source officielle.

## Matrice de non-régression

| Fonction existante | Emplacement actuel | Nouvel emplacement | Test effectué | OK/KO |
|---|---|---|---|---|
| Accès à la console administrateur | Profil + rail accueil → `AdminScreen` | Console admin → Tableau de bord + accès “Gardes & validations historiques” | Inventaire statique baseline | OK |
| Vue synthétique comptes/demandes | `AdminScreen._AdminSummary` | Console admin → Tableau de bord | À tester après refonte | À TESTER |
| Filtre établissement | `AdminScreen` | Console admin → Médecins & utilisateurs / Gardes & validations | Inventaire statique baseline | OK |
| Recherche médecin | `AdminScreen` | Console admin → Médecins & utilisateurs / Gardes & validations | Inventaire statique baseline | OK |
| Sélection médecin | `AdminScreen` | Console admin → Gardes & validations | Inventaire statique baseline | OK |
| Calendrier individuel administrateur | `AdminScreen._DoctorCalendar` | Console admin → Gardes & validations | À tester après refonte | À TESTER |
| Suppression admin d'une garde autorisée | `AdminScreen._confirmDeleteShift` + RPC | Console admin → Gardes & validations | À tester règles/protections | À TESTER |
| Validation définitive d'un mois | `AdminScreen._confirmReviewPlanningMonth` | Console admin → Validations + accès historique | À tester | À TESTER |
| Rejet / demande de correction d'un mois | `AdminScreen._confirmReviewPlanningMonth` | Console admin → Validations + accès historique | À tester | À TESTER |
| Dévalidation / réouverture d'un mois | `AdminScreen._confirmReopenPlanningMonth` + RPC | Console admin → Validations + accès historique | À tester | À TESTER |
| Gestion promotion d'internat | `AdminScreen._PromotionManagementCard` | Console admin → Paramètres & maintenance | À tester | À TESTER |
| Validation/refus des comptes | `AdminScreen` + `NotificationsScreen` | Console admin → Médecins & utilisateurs | À tester | À TESTER |
| Gestion demandes de mot de passe | `NotificationsScreen` + `AdminPasswordResetScreen` | Console admin → Médecins & utilisateurs | À tester | À TESTER |
| Suppression définitive d'un compte | `AdminPasswordResetScreen` | Console admin → Médecins & utilisateurs | À tester avec protections | À TESTER |
| Notifications / alertes | `NotificationsScreen` | Console admin → Notifications | À tester | À TESTER |
| Transferts / échanges en attente | `NotificationsScreen` | Console admin → Échanges / transferts / demandes | À tester | À TESTER |
| Congés en attente | `NotificationsScreen` | Console admin → Validations / demandes | À tester | À TESTER |
| Acceptation/refus destinataire d'un échange | `AppState.acceptExchange/declineExchange` | Inchangé métier ; surface Notifications | À tester | À TESTER |
| Approbation/rejet admin d'un échange | `AppState.approveExchange/rejectExchange` | Console admin → Échanges / transferts / demandes | À tester | À TESTER |
| Annulation d'un échange | `AppState.cancelExchange` | Console admin / Notifications | À tester | À TESTER |
| Transfert de garde | `ExchangeRequestSheet` + `AppState.createTransferRequest` | Règle métier inchangée ; accès console demandes | À tester | À TESTER |
| Échange de garde | `ExchangeRequestSheet` + `AppState.createSwapRequest` | Règle métier inchangée ; accès console demandes | À tester | À TESTER |
| Règle même hôpital | `BusinessRules.sameHospitalRequired` | Inchangée | Test existant + non-régression à relancer | À TESTER |
| Règle même service pour échange Service | `BusinessRules.exchangeRequiresSameService` | Inchangée | Test existant + non-régression à relancer | À TESTER |
| Règle promotion pour Urgences | `BusinessRules.firstYearSamePromotionRequiredForEmergency` | Inchangée | Test existant + non-régression à relancer | À TESTER |
| Protection gardes disciplinaires | Triggers/RPC + `is_disciplinary` | Inchangée ; Console admin → Gardes disciplinaires | À tester | À TESTER |
| Attribution manuelle garde disciplinaire | `AdminDisciplinaryAssignmentScreen` | Console admin → Gardes disciplinaires | À tester | À TESTER |
| Lecture marques rouges du planning officiel | Import officiel + règles disciplinaires | Console admin → Lecture PDF / vérification | À tester | À TESTER |
| Consultation PDF officiel | `OfficialPlanningScreen` + viewer | Console admin → Plannings officiels | À tester | À TESTER |
| Recherche dans viewer PDF | `_OfficialPdfViewerScreen` | Conservée | À tester | À TESTER |
| Upload PDF officiel | `OfficialPlanningScreen._upload` | Console admin → Lecture PDF / Import | À tester | À TESTER |
| Préflight PDF avant publication | `analyzeOfficialRosterPreflight` | Console admin → Lecture PDF / Import | À faire évoluer A+B(+C) | À TESTER |
| Version active du planning | `shared_resources` | Console admin → Plannings officiels | À tester | À TESTER |
| Historique des versions officielles | `official_roster_versions` + `list_official_roster_versions` | Console admin → Plannings officiels → Historique | À tester | À TESTER |
| Versions immuables R4 | migration R4 | Conservé sans régression | À tester SQL | À TESTER |
| Anti-downgrade du parseur R4 | RPC `*_v2` | Conservé, seuil relevé pour nouvelle révision | À tester SQL | À TESTER |
| Couverture fail-closed R4 | `guardeflow_preserve_uncovered_official_dates` | Conservée + contrôles renforcés | À tester | À TESTER |
| Continuité des dates R4/R5 | parseur + `_validateCoverage` | Conservée + contrôleur indépendant | À tester | À TESTER |
| Fusion historique des versions | `readVersionHistory` / `mergeNewestFirst` | Conservée | Test existant à relancer | À TESTER |
| Double lecture vérifiée R5 | Edge Function `analyze-official-roster-pdf` | Moteur R6 : Lecture A locale structurée + Lecture B visuelle indépendante | À remplacer/tester | À TESTER |
| Troisième lecture actuelle | Edge Function, actuellement systématique | Lecture C **conditionnelle uniquement** | À remplacer/tester | À TESTER |
| Blocage si lectures non fiables | Edge Function + confidence >= 0,90 | Statuts VERT/ORANGE/ROUGE + fail-closed | À tester | À TESTER |
| Import global officiel | RPC `import_official_emergency_roster_v2` | Publication depuis source officielle validée | À sécuriser/tester | À TESTER |
| Synchronisation profil depuis planning officiel | `_syncOfficialRosterForProfile` | Recalcul dérivé depuis source officielle + lien d'identité | À faire évoluer/tester | À TESTER |
| “Refaire la superposition” utilisateur | `OfficialPlanningScreen._resyncMyRoster` | Conservé + Console admin → recalcul individuel/global | À tester | À TESTER |
| Blocage recalcul si calendrier validé | `OfficialPlanningScreen` + protections DB | Conservé selon règle existante | À tester | À TESTER |
| Données officielles indépendantes des entrées personnelles | Partiel : version PDF distincte, mais gardes non matérialisées sans compte | Nouvelle table officielle dédiée | À implémenter/tester | À TESTER |
| Journal administratif | `AuditScreen` + `audit_log` | Console admin → Logs & traçabilité | À tester | À TESTER |
| Nettoyage journal | `AuditScreen._clearAudit` | Console admin → Logs & traçabilité | À tester | À TESTER |
| Thème application | `ApplicationSettingsScreen` | Paramètres application (hors règles métier) | À tester | À TESTER |
| Rappels/alarme de garde | `SettingsScreen` + NotificationService | Inchangé ; Console admin ne modifie pas la logique utilisateur | Tests non-régression | À TESTER |
| Rappels avant garde | `AppState.setReminderDelays` etc. | Inchangé | À tester | À TESTER |
| Rescheduling rappels après backend | `_syncCurrentUserRemindersAfterBackend` | Inchangé | À tester | À TESTER |
| Realtime planning | `AppState._startRealtime` | Inchangé | À tester | À TESTER |
| Annuaire / contacts | `DirectoryScreen` / backend | Hors refonte métier, conserver | Smoke test | À TESTER |
| Astreintes séniors/juniors | écrans Astreinte | Hors module Garde officiel ; aucune modification implicite | Smoke test | À TESTER |
| Practice / QCM / cas cliniques | écrans/services Practice | Hors périmètre ; aucune régression autorisée | Suite existante | À TESTER |

## Nouvelles capacités à ajouter

| Nouvelle capacité | Emplacement cible | Test attendu | État |
|---|---|---|---|
| Source officielle contenant aussi les médecins non inscrits | DB + service roster | Médecin sans compte reste visible avec toutes ses gardes | À FAIRE |
| Identité officielle prénom + nom + nom complet | Modèle/table officielle | Jamais d'attribution sur nom/prénom seul | À FAIRE |
| Normalisation prudente d'identité | Service identité | Accents/tirets/apostrophes/espaces seulement | À FAIRE |
| Matching exact prioritaire | Service identité | 1 seul candidat exact → liaison possible | À FAIRE |
| Fuzzy uniquement comme suggestion | Service identité | Aucun auto-link sur fuzzy | À FAIRE |
| Homonymie / correspondance ambiguë | Import + console | Import gardé, attribution personnelle bloquée | À FAIRE |
| Liaison persistante identité officielle ↔ compte | DB + console | CRUD tracé et réutilisé | À FAIRE |
| Détection nouveau compte ↔ médecin historique | DB + console | Suggestion sans auto-attribution | À FAIRE |
| Lecture A réellement indépendante | Parseur local structuré | Résultat brut sans dépendre des profils | À FAIRE |
| Lecture B réellement indépendante | Vérification visuelle distante | Résultat brut sans contexte profils | À FAIRE |
| Comparateur garde par garde A/B | Service roster | Date/identité/type/période/lieu/comptages | À FAIRE |
| Lecture C conditionnelle | Edge Function + orchestration | Aucun appel C si A=B+contrôles OK | À FAIRE |
| Statut VERT | moteur | A=B + contrôles structurels OK | À FAIRE |
| Statut ORANGE | moteur | conflit résolu par C + contrôles OK | À FAIRE |
| Statut ROUGE | moteur | ambiguïté restante → publication bloquée | À FAIRE |
| Score de confiance par garde | modèle/table + console | faible score jamais injecté silencieusement | À FAIRE |
| Contrôles de complétude indépendants | service | jours/lignes/colonnes/cellules/comptages/doublons | À FAIRE |
| Rapport d'import complet | DB + console | métriques, anomalies, corrections, moteur | À FAIRE |
| Validation humaine ciblée | Console → Vérification import | admin ne revoit que conflits/faibles scores | À FAIRE |
| Recalcul individuel avec aperçu | Console → Superpositions | diff ajout/retrait/modif/inchangé avant apply | À FAIRE |
| Recalcul global avec aperçu | Console → Superpositions | diff global + validation explicite | À FAIRE |
| Recalcul sans mutation de la source officielle | DB/RPC | hash/contenu source identique avant/après | À FAIRE |
| Audit import/C/correction/mapping/recalcul | `audit_log` + nouvelles métadonnées | événement complet avant/après/résultat | À FAIRE |
| Jeux de non-régression historiques | `source/test/fixtures` | 100 % attendu, 0 extra, 0 mauvaise attribution | BLOQUÉ : aucun PDF historique versionné dans le dépôt |
| Tests médecins non inscrits/homonymes/composés | tests unitaires/intégration | cas synthétiques exhaustifs + futurs PDF historiques | À FAIRE |

## Garde-fous de migration

1. Ne pas supprimer `AdminScreen`; la nouvelle console l'encapsule comme module historique pendant la migration.
2. Ne pas modifier les constantes de `BusinessRules`.
3. Ne pas modifier implicitement les RPC métier d'échanges/congés/validation.
4. Les nouvelles données officielles sont la source de vérité ; `planning_entries` reste une couche dérivée pour les comptes liés.
5. Aucun fuzzy matching ne crée automatiquement un `profile_id`.
6. Toute anomalie critique bloque la publication.
7. R4 reste un minimum de sécurité : aucune couverture/date précédemment protégée ne doit pouvoir disparaître.
8. La branche ne sera pas fusionnée sur `main` tant que toutes les lignes applicables de cette matrice ne sont pas **OK**.
