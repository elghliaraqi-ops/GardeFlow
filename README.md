# GardeFlow — Android + notifications push — V11.1.5

**Commencer par [DEMARRAGE_ANDROID.md](DEMARRAGE_ANDROID.md).**
Le guide ci-dessous est l’historique du projet ; pour Android, utiliser désormais
`tool/android.ps1`, qui configure Firebase, Gradle et les notifications.

# HUIM6 Planning des gardes — V5 consolidée

Application Flutter de planning des gardes : comptes médecins/admin, calendrier,
annuaire, gardes Service/Urgences, congés, échanges avec règles métier par type de garde,
photos d'astreinte, rappels et vue administrateur par médecin.

## V11.6.0 — Transposition automatique des plannings Urgences

Après application de `PATCH_SUPABASE_V11_6_0_OFFICIAL_PDF_AUTO_IMPORT.sql`, les PDF du bouton **Planning de Garde Officiel** sont analysés automatiquement par l'application. Les cases 08h–20h, 20h–08h et les grandes cases 24H sont converties respectivement en `urg-jour`, `urg-nuit` et `urg-24h` dans les calendriers individuels des médecins reconnus.

Les PDF déjà stockés dans Supabase sont repris automatiquement au premier passage d'un administrateur sur cette page ; aucun nouvel upload n'est requis.
