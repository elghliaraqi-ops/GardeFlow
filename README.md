# GardeFlow — V11.6.0

Application Flutter de planning des gardes pour le réseau HUIM6 / HUICK.

## V11.6.0 — Transposition automatique des plannings Urgences

Les PDF déjà publiés dans **Planning de Garde Officiel** peuvent désormais être analysés automatiquement pour préremplir les calendriers individuels :

- **08h–20h** → `urg-jour`
- **20h–08h** → `urg-nuit`
- **grande cellule fusionnée** → `urg-24h`

Les gardes reconnues sont transposées automatiquement, sans validation admin intermédiaire. Le médecin peut ensuite les modifier tant que son mois n'est pas validé définitivement.

### Fichiers principaux V11.6.0

- `lib/services/official_roster_import_service.dart` — lecture structurée des PDF et rapprochement des médecins
- `lib/screens/official_planning_screen.dart` — déclenchement automatique de la transposition
- `lib/services/supabase_backend_service.dart` — appels RPC Supabase
- `PATCH_SUPABASE_V11_6_0_OFFICIAL_PDF_AUTO_IMPORT.sql` — migration à exécuter une fois dans Supabase
- `supabase/patch_v11_6_0_official_pdf_auto_import.sql` — copie de la migration dans le dossier Supabase
- `CHANGELOG_V11_6_0.md` — détail fonctionnel
- `MIGRATION_V11_6_0.md` — procédure de migration

## Migration

1. Exécuter `PATCH_SUPABASE_V11_6_0_OFFICIAL_PDF_AUTO_IMPORT.sql` dans **Supabase → SQL Editor**.
2. Compiler/installer GardeFlow V11.6.0.
3. Se connecter avec un compte admin et ouvrir **Planning de Garde Officiel**.
4. Les PDF déjà présents seront analysés automatiquement.

Les mois déjà validés définitivement ne sont jamais modifiés par l'import automatique.
