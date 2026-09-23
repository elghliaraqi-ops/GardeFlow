# GardeFlow — V12

GardeFlow est l’application Flutter de gestion des gardes médicales du réseau HUIM6 / HUICK.

## Source de référence

À partir de **V12**, l’application complète et consolidée se trouve dans **`source/`**.

Les dizaines de correctifs historiques V11.6.x ont été intégrés directement dans cette source. Les builds de production ne reconstruisent plus l’application en rejouant la chaîne de patches : Android, Web et iOS compilent désormais `source/` directement.

- Version : **12.0.0+300**
- Flutter : `source/lib/`
- Tests : `source/test/`
- Outils de génération Android/iOS : `source/tool/`
- Backend versionné : `source/supabase/` et `supabase/`
- Documentation d’optimisation : `source/V12_OPTIMISATION.md`

Les dossiers `ci/v11_6_*` et les anciens fichiers V11 restent uniquement comme **historique technique**. Ils ne constituent plus la chaîne de build V12.

## Règles métier conservées

V12 conserve les règles métier validées de GardeFlow : planning JOUR / NUIT / 24H, Service et Urgences, congés, validation mensuelle, échanges et transferts, gardes disciplinaires, promotions d’internat, astreintes juniors et seniors, annuaire, planning officiel, notifications et alarmes de garde.

Les mois passés restent en lecture seule. Les échanges inter-établissements sont interdits. Les échanges de gardes de service restent soumis aux règles de même service, tandis que les opérations nécessitant une validation administrative conservent leur circuit dédié.

## Builds

Les workflows V12 principaux sont :

- `.github/workflows/build-android-apk.yml`
- `.github/workflows/build-web-v12.yml`
- `.github/workflows/build-ios.yml`
- `.github/workflows/build-ios-signed.yml`

Ils compilent tous la source consolidée, sans empilement de patches V11.

## Sauvegarde

L’état de `main` antérieur à la migration V12 est conservé dans la branche :

`backup-main-pre-v12-20260923`
