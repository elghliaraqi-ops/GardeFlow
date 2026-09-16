# GardeFlow V11.6.0 — Import automatique des gardes Urgences

## Fonction ajoutée

Les PDF déjà publiés dans **Planning de Garde Officiel** servent désormais de source pour préremplir automatiquement les calendriers individuels.

Le lecteur utilise directement le texte structuré et les coordonnées du PDF via `pdfrx` :

- colonne **08h–20h** → `urg-jour` ;
- colonne **20h–08h** → `urg-nuit` ;
- cellule fusionnée centrée sur toute la largeur → `urg-24h`.

Les noms détectés sont rapprochés des comptes actifs du même établissement. Les gardes reconnues sont transposées automatiquement, sans validation admin intermédiaire.

## Comportement métier

- Un mois déjà **validé définitivement** n'est jamais modifié par l'import.
- Une date déjà saisie/modifiée manuellement par le médecin reste prioritaire et n'est pas écrasée.
- Une garde importée reste modifiable par son médecin tant que les règles habituelles du calendrier l'autorisent et que le mois n'est pas validé.
- Dès qu'un médecin modifie une garde importée, elle est détachée de la source PDF afin qu'un nouvel affichage du même PDF ne rétablisse pas l'ancienne valeur.
- Un même PDF/version n'est importé qu'une fois.
- Lorsqu'un PDF est remplacé, la nouvelle version est analysée automatiquement.
- Les PDF déjà présents avant V11.6.0 sont analysés automatiquement la première fois qu'un administrateur ouvre **Planning de Garde Officiel**.

## Robustesse du format réel

Le parseur accepte :

- les dates `jj/mm` ou `jj/mm/aaaa` ;
- plusieurs médecins dans une même cellule ;
- les noms écrits `NOM Prénom` ou `Prénom NOM` ;
- les accents, tirets et le préfixe `Dr` ;
- une petite faute typographique dans un nom via rapprochement conservateur ;
- une coquille évidente de mois dans une suite quotidienne (ex. `27/08, 28/09, 29/08` → `28/08`).

## Migration Supabase obligatoire

Exécuter une seule fois :

`PATCH_SUPABASE_V11_6_0_OFFICIAL_PDF_AUTO_IMPORT.sql`

Le patch ajoute uniquement la traçabilité de la source PDF, l'historique des imports et le RPC d'import sécurisé réservé aux administrateurs.
