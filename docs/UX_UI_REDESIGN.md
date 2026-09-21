# GardeFlow — refonte UX/UI 11.7

## Base vérifiée avant modification

Branche de référence : `audit-fixes-v11.6.70`, commit `c6881880b43ff1754cfb2147d0bb674e8924691b` (APK compilée avec succès). `main` est resté en 11.6.67 ; repartir de `main` ferait perdre les corrections récentes. Le projet compilé est dans `source/`, et non dans les quelques fichiers historiques de `lib/` à la racine.

L'application utilise **Provider / ChangeNotifier**, pas Riverpod. Aucune migration de gestion d'état n'est incluse. Les modèles, services, AppState, règles et SQL sont protégés par un inventaire SHA-256 (`ux-business-baseline.json`). Aucune opération de migration ou de déploiement Supabase n'est nécessaire.

## Audit des écrans et des parcours

| Écran | Constat avant refonte | Décision UX |
|---|---|---|
| Accueil | 3 450 lignes mêlant coque, dashboard et calendrier ; grande salutation colorée ; garde en cours absente de la priorité visuelle | Garde du jour d'abord, prochaine garde, statistiques et état du mois, calendrier puis actualités |
| Planning personnel | Grille contrainte à la hauteur restante ; libellés réduits par FittedBox ; croix de 18–26 px chevauchant les dates | Grille mensuelle sans défilement horizontal ; journée entière tactile ; fiche de détail ; palette de placement lisible |
| Détail de garde | Clic ouvrant directement un échange et actions microscopiques sur la grille | Fiche avec lieu, horaires, état et actions autorisées ; indisponibilités expliquées avant clic |
| Échanges / transferts | Recherche puis dropdown : deux interactions pour retrouver un collègue | Résultats immédiatement visibles avec initiales ; sélection explicite ; formulaire adapté au clavier |
| Notifications | Plusieurs cartes et petits onglets ; nombre agrégé correspondant aux actions à traiter | Boîte de demandes intégrable ; catégories existantes conservées ; compteur « à traiter » fidèle à sa signification |
| Astreintes juniors | Nombreux filtres et hauteurs fixes ; appel présent mais petit | Bascule commune Juniors/Seniors ; lignes lisibles ; accès calendrier et appel conservés |
| Astreintes seniors | Galerie de photos par établissement avec zoom ; upload/suppression admin | Galerie et visualiseur conservés, surfaces et titres harmonisés |
| Planning officiel | Publication, suppression, lecture PDF, import et resuperposition couplés dans l'écran | Liste des établissements claire ; tous les workflows et restrictions conservés |
| Annuaire | Catégories avant recherche ; apparence de cartes répétées ; appel générique pour extensions | Recherche en premier ; lignes ; extensions hospitalières identifiées et copiables |
| Profil | Mélange identité, menus administratifs et paramètres | Identité et compte ; destinations regroupées dans Plus ; paramètres séparés |
| Rappels | Autorisations natives, tests et persistance directement dans l'écran | Conserver les opérations et les réglages ; présentation hiérarchisée et adaptable |
| Apparence | Palette globale mutable ; couleurs profondes saturées ; choix trop étroits | ColorScheme complet, surfaces sobres, quatre palettes et aperçu du choix |
| Administration | Résumés, trois filtres et calendrier sur une même page | Accueil administratif par sections ; calendrier dédié après établissement/médecin |
| Historique | Timeline déjà fonctionnelle ; filtres étroits | Conserver recherche/filtres et confirmations, harmoniser lecture et contraste |
| Gestion des comptes | Réinitialisation et suppression couplées au backend | Garder les contrôles, confirmations et mutations existants |
| Connexion / inscription / récupération | FittedBox global rétrécissant tout le formulaire ; couleurs ponctuelles | Formulaire avec largeur limitée, défilement de secours au clavier, thème partagé |
| Splash | Fonds clairs codés en dur, indépendants du thème | Identité existante sur surface du thème et transition courte |
| Alarme Android native | Activity plein écran créée par script, indépendante du thème Flutter | Conserver intents, arrêt/rappel et verrouillage ; présentation native simple |

Recherche statique : 173 occurrences de couleurs explicites dans les écrans (incluant blanc/noir légitimes des visualiseurs), nombreuses hauteurs fixes et textes entre 8 et 11 px. Une hauteur fixe de SizedBox d'espacement n'est pas en elle-même un défaut. Les risques principaux concernent les lignes non flexibles, les formulaires et les grilles contraintes.

## Architecture retenue

- `theme/app_theme.dart` : palettes, ColorScheme, typographie, espacements, rayons, états et thèmes Material. Façade `AppColors` conservée pour les anciens composants ; pas de changement de persistance des préférences.
- `ui/components.dart` : sections, badges de statut, identité médecin, états vides, boutons et bottom sheets adaptés au clavier.
- `widgets/planning_calendar.dart` : grille de présentation commune, avec callbacks et indicateurs accessibles.
- `screens/shift_details_sheet.dart` : détail de journée et placement appelant les méthodes AppState existantes.
- Coque à quatre destinations : Accueil / Planning / Demandes / Plus. Plus donne accès à l'annuaire, aux astreintes, aux documents, au profil, aux rappels, à l'apparence et à l'administration.
- Espace administrateur par sections ; les écrans de gestion existants restent les points d'entrée des mutations.

## Invariants et écarts de terminologie à respecter

Dans cette version, `submitMyPlanningMonth` effectue une **validation définitive** ; il ne faut pas introduire une nouvelle étape d'approbation pour satisfaire une formulation graphique. Les anciens états submitted/rejected restent traités comme prévu par AppState.

Les gardes de service et urgences peuvent participer à certains échanges mixtes selon les contrôles existants : seul AppState/backend décide des destinataires et compatibilités. Ne pas limiter arbitrairement les choix.

Le badge global compte les **actions à traiter**, pas des notifications non lues : aucun champ de lecture ou événement fictif n'est ajouté. Les demandes de récupération de compte sont déjà intégrées à l'onglet Comptes.

Les seniors sont actuellement exposés sous forme de photos/documents. Une photo n'est pas transformée en annuaire structuré inventé. Les appels utilisent les coordonnées réellement présentes.

## Vérification

Gates prévus : analyse Flutter, tests ciblés, compilation Android dans la CI du projet. Tests de contraste des quatre palettes, petits écrans, texte agrandi, clavier, calendrier et disponibilité des actions. Les tests de push existants restent exécutés. Contrôle des empreintes métier/SQL avant livraison. L'état réel d'exécution figure ci-dessous.

Les vérifications automatisées locales/CI ne remplacent pas un essai de réception FCM et de réveil plein écran sur un téléphone Android réel, ni un parcours authentifié sur Supabase. Ces limites doivent apparaître dans la livraison.

Référence accessibilité : https://docs.flutter.dev/ui/accessibility (contraste 4,5:1, cibles tactiles et mise à l'échelle du texte).

## Lot préparé sur `ux-ui-refonte-v11.7.0` — 21 septembre 2026

Le code de la refonte est enregistré localement. Il reste à passer les gates Flutter avant de considérer cette version comme livrable.

| Parcours | Changements préparés | Fonctionnement conservé |
|---|---|---|
| Thèmes | Quatre ColorScheme complets ; palette de gardes centralisée dans AppShiftTheme ; typographie, boutons, formulaires, dialogues et badges communs | Préférence existante et gestion d'état Provider |
| Navigation | Accueil, Planning, Demandes, Plus ; administration par sections | Toutes les destinations restent accessibles |
| Accueil | Garde actuelle, y compris la nuit commencée la veille ; horaires et lieu ; prochaine garde ; nombre mensuel ; état du mois ; demandes ; calendrier ; actualités | Données réelles AppState et flux d'actualités existant |
| Planning | Calendrier partagé avec la vue admin ; mois complet sans défilement horizontal ; détail en bottom sheet ; palette tactile et glisser-déposer ; mois passés en lecture seule | placeShift, removeShift, submitMyPlanningMonth et droits existants |
| Échanges / transferts | Recherche avec résultats visibles ; explications et désactivation des incompatibilités connues avant envoi | Mêmes destinataires, règles de service/établissement, acceptations et validations |
| Notifications | Catégories existantes lisibles ; compteur de demandes à traiter ; nettoyage conservé ; confirmations administratives | Comptes, récupération, congés, échanges/transferts et filtrage par compte |
| Astreintes | Bascule Juniors/Seniors ; lignes de médecins avec appel ; galeries adaptables et défilantes | Coordonnées disponibles, upload admin, photos, navigation et zoom |
| Documents | Présentation des établissements et des synthèses harmonisée | PDF intégrés, zoom, recherche, import/superposition, publication et suppression admin |
| Annuaire | Recherche prioritaire ; résultats en lignes ; extensions explicitement hospitalières et copiables | Filtres, contacts, gestion admin et appel des numéros ordinaires |
| Profil / paramètres | Identité séparée ; rappels ; apparence avec aperçu ; signature et version | Déconnexion, préférences, autorisations et tests de rappel existants |
| Administration | Entrées par sections ; choix explicite du médecin ; calendrier confortable ; historique plus lisible | Vérification des comptes, réinitialisation, réouverture, suppressions et motifs |
| Alarme native | Type, horaire extrait du message existant, Rappel dans 9 min et Arrêter ; disposition défilante pour les petits écrans | Manifest, conditions de démarrage, identifiant d'alarme et dispatch des actions inchangés |

### Contrôles réellement exécutés

- `python source/tool/check_ui_business_boundary.py` : **67 fichiers métier/backend identiques** à la base.
- `node --test test/push_payload_test.mjs test/push_recipient_test.mjs`, depuis `source/` : **9 tests réussis**, hors réseau. Les nouveaux cas vérifient les destinataires et les messages natifs sans affichage automatique avant contrôle du compte.
- Analyse syntaxique Tree-sitter : **60 fichiers Dart sans erreur de syntaxe ni argument nommé dupliqué**. Ce contrôle ne remplace pas `flutter analyze`.
- Assemblage de l'AlarmActivity dans un répertoire temporaire : script de présentation exécuté avec succès ; manifest, contrôles de démarrage et fonction d'envoi des actions arrêt/rappel comparés à l'original et identiques.
- Contrôle des appels AppState : les opérations référencées par les anciens écrans principaux restent accessibles dans les écrans réorganisés et leurs helpers UI.
- `git diff --check` : aucune erreur après nettoyage.

### À exécuter avant livraison

Flutter et Dart ne sont pas installés dans cet environnement. Le téléchargement officiel du SDK a échoué au niveau du proxy. **Ni `flutter analyze`, ni les tests Flutter, ni la compilation APK n'ont été exécutés pour cette refonte. Aucun APK 11.7.0 ni aperçu issu de son rendu réel n'est encore disponible.**

La CI `ux-ui-validation.yml` prépare Flutter 3.47.5, la configuration Android/Firebase existante, l'analyse, les tests, les captures des quatre thèmes et l'APK. Elle cible uniquement la branche de refonte. Les tests Flutter ajoutés couvrent notamment le badge Rouvert, les gardes disciplinaires avant/après validation, les mois passés, les rôles, l'échange Jour/Nuit le même jour, les workflows Service/Urgences/transfert, le texte agrandi et le clavier.

Le premier envoi avait été refusé par le contrôle automatique faute d'autorisation explicite. L'utilisateur a ensuite explicitement autorisé l'envoi de `ux-ui-refonte-v11.7.0` vers `elghliaraqi-ops/GardeFlow` pour lancer les vérifications et produire l'APK. La tentative autorisée a échoué : Git ne dispose pas d'authentification et le connecteur GitHub renvoie `HTTP 400: Invalid MCP request metadata`, y compris après sélection explicite de `@GitHub`. La branche n'est donc pas encore sur GitHub. Le blocage actuel est technique ; l'autorisation est acquise dans cette conversation.

### Limites fonctionnelles explicites

- Le compteur existant mesure les actions à traiter. Un véritable état « lu/non lu » par événement nécessiterait une évolution de données, hors de cette refonte conservatrice.
- Les astreintes seniors sont des documents/photos dans le modèle actuel : aucun annuaire de seniors fictif n'a été créé.
- Le message d'alarme actuel ne transporte pas l'établissement ; l'écran ne l'invente pas. Ajouter cette donnée au réveil natif nécessiterait une évolution explicite du payload.
- `supabase/functions` et `source/supabase/functions` diffèrent déjà dans la base 11.6.70. Les deux ensembles sont conservés et testés séparément ; aucun déploiement Supabase n'a été effectué.
- Les écrans interactifs, les contrastes rendus et les débordements doivent encore être confirmés par les tests Flutter et une revue des captures. Les notifications réelles, l'accès Supabase authentifié et le réveil Android doivent être essayés sur appareil.

### Reprise

1. Reprendre avec un connecteur GitHub fonctionnel et envoyer `ux-ui-refonte-v11.7.0` vers `elghliaraqi-ops/GardeFlow` pour déclencher la CI dédiée, conformément à l'autorisation donnée.
2. Examiner `analysis.log`, les résultats des tests et les captures ; corriger les erreurs éventuelles sur cette branche.
3. Vérifier l'APK sur appareil puis livrer l'artefact. Aucun merge vers `main` n'est inclus dans cette étape.
