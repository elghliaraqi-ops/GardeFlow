# Reprise de GardeFlow 11.7.0

## Objectif immédiat

Terminer la validation technique de la refonte UX/UI déjà implémentée, corriger les erreurs éventuelles, puis fournir l'APK et les captures réelles des quatre thèmes. L'utilisateur souhaite terminer rapidement. La prochaine étape est l'envoi de la branche et l'exécution de la CI.

## Sources et état exact

- Dépôt : https://github.com/elghliaraqi-ops/GardeFlow
- Branche de travail : `ux-ui-refonte-v11.7.0`.
- Base conservée : `audit-fixes-v11.6.70`, commit `c6881880b43ff1754cfb2147d0bb674e8924691b`.
- Commits locaux du travail UI : `4a885ef` (architecture, thèmes et premiers tests), puis `4dc7c34` (refonte des parcours et finitions).
- Version de l'application : `11.7.0+231`.
- Le projet réellement compilé se trouve dans **`source/`**. Les fichiers `lib/` de la racine sont historiques ; `main` était encore en 11.6.67 au début du travail.
- Le ZIP est un export complet des fichiers suivis par Git, avec les nouveaux documents de reprise. Il ne contient pas le répertoire `.git`.
- Aucune branche distante de refonte n'a été créée et aucun APK 11.7.0 n'a été compilé.

Le code implémenté, les décisions UX et le détail des limites sont dans `docs/UX_UI_REDESIGN.md`. Ce document de reprise et le ZIP suffisent pour retrouver le travail sans relire la conversation précédente.

## Autorisation et incident technique

L'utilisateur a répondu **« Oui »** à la demande explicite d'envoyer la branche `ux-ui-refonte-v11.7.0` sur `elghliaraqi-ops/GardeFlow` pour lancer les tests et produire l'APK. Il a ensuite sélectionné `@GitHub` et demandé de transférer la tâche vers une conversation où le connecteur fonctionne.

L'envoi Git autorisé a échoué avec `could not read Username for https://github.com`. Les lectures du connecteur ont échoué avec `HTTP 400: Invalid MCP request metadata`. Cette erreur précède l'accès au dépôt. Aucune modification distante n'a été effectuée. Aucun merge vers `main`, changement de données ou déploiement Supabase n'a été demandé.

## Préserver les fonctionnalités

La refonte conserve AppState, les modèles, les services, Firebase/FCM, Supabase, les règles SQL/RLS et les paramètres existants. **L'implémentation réelle utilise Provider/ChangeNotifier, pas Riverpod** ; conserver ce mécanisme.

`docs/ux-business-baseline.json` protège 67 fichiers par SHA-256. Le script `source/tool/check_ui_business_boundary.py` doit continuer à réussir. Les deux répertoires `supabase/functions` et `source/supabase/functions` différaient déjà dans la base : aucun des deux n'a été changé.

Règles essentielles : échanges dans le même établissement ; implication d'une garde de service limitée au même service ; échange Service/Service appliqué dès acceptation ; échange impliquant les Urgences et transfert soumis à validation admin ; grade junior/senior indépendant des droits admin ; garde disciplinaire protégée avant et après validation ; mois passés en lecture seule. Le moteur actuel valide définitivement le mois via `submitMyPlanningMonth` : aucune nouvelle étape d'approbation n'a été inventée.

## Vérifications déjà exécutées

- 67 fichiers métier/backend inchangés.
- 9 tests Node de notifications réussis, avec mocks réseau et contrôle des destinataires.
- 60 fichiers Dart parsés sans erreur syntaxique ni argument nommé dupliqué. Ce n'est pas une analyse Flutter.
- Script natif d'alarme exécuté sur un projet temporaire ; manifest, conditions de démarrage et dispatch des actions arrêt/rappel conservés.
- Appels AppState des anciens écrans principaux retrouvés dans la nouvelle organisation.
- `git diff --check` propre.

**Non exécutés : `flutter analyze`, tests Flutter, compilation APK, inspection des captures, essai Supabase authentifié, réception FCM et réveil plein écran sur appareil.** Flutter/Dart sont absents de l'ancien environnement et le téléchargement officiel du SDK y échouait au proxy.

## Procédure de reprise

1. Vérifier le dépôt et la branche distante, au cas où ils auraient évolué depuis cet export. Cloner le dépôt à partir de `audit-fixes-v11.6.70`, créer la branche de refonte si elle est absente et appliquer les fichiers de ce ZIP. Préserver l'historique de la base ; ne pas forcer une branche existante sans examiner ses changements.
2. Lire `docs/UX_UI_REDESIGN.md`, vérifier les empreintes métier, puis enregistrer et envoyer les fichiers sur `ux-ui-refonte-v11.7.0`.
3. Suivre **`GardeFlow UX UI validation`**, fichier `.github/workflows/ux-ui-validation.yml`. Ce workflow utilise `source/` directement avec Flutter 3.47.5 et Node 22.14.0. Le vieux workflow Android et sa chaîne de patchs historiques ne constituent pas le chemin de compilation de cette branche.
4. Corriger les erreurs de l'analyse et des tests sur cette branche. Ne pas désactiver les tests pour obtenir un APK. Les tests Flutter incluent les petits écrans, les quatre palettes, le badge Rouvert, le clavier, les rôles, les gardes disciplinaires, les échanges Jour/Nuit le même jour et les validations.
5. Examiner les captures de `source/test/previews/home-*.png` produites par les tests et les journaux dans l'artefact `GardeFlow-11.7-validation` ; corriger les problèmes rendus avant livraison.
6. Récupérer l'artefact `GardeFlow-v11.7.0-apk` après succès, vérifier l'APK et le fournir à l'utilisateur. Présenter honnêtement les essais sur appareil restant à faire.

La CI configure Android et Firebase à partir des fichiers existants, applique l'installateur natif d'alarme d'origine puis `source/tool/style_alarm_activity.py`, exécute l'analyse, les tests Flutter/Node et compile en release.
