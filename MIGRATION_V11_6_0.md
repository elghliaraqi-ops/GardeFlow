# Migration V11.6.0

1. Dans **Supabase → SQL Editor**, exécuter intégralement :
   `PATCH_SUPABASE_V11_6_0_OFFICIAL_PDF_AUTO_IMPORT.sql`.
2. Installer/compiler GardeFlow V11.6.0.
3. Se connecter une fois avec un compte administrateur et ouvrir **Planning de Garde Officiel**.
4. Les PDF officiels déjà présents sont analysés automatiquement. Aucune ré-upload n'est nécessaire.
5. Les futurs remplacements de PDF déclenchent la transposition juste après l'upload.

### Important

Aucune étape de validation admin n'est ajoutée. Les gardes reconnues sont directement placées dans les calendriers brouillons des médecins. Les mois déjà validés définitivement ne sont pas modifiés.
