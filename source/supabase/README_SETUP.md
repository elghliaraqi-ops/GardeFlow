# Configuration Supabase — HUIM6 Planning V10.2

## Authentification retenue

L'utilisateur voit uniquement **numéro de téléphone + mot de passe**. Aucun OTP, aucun SMS et aucun fournisseur SMS n'est nécessaire.

En interne, l'application normalise le téléphone puis fabrique un identifiant technique :

```text
0707099802
→ +212707099802
→ 212707099802@VOTRE-PROJET.supabase.co
```

Cette adresse technique est construite avec le domaine du projet Supabase et n'est jamais affichée au médecin. Le vrai numéro reste stocké dans `public.profiles.phone`.

## Réglages Supabase Auth

Dans **Authentication > Providers** :

1. laissez **Email** activé ;
2. désactivez **Confirm email** ;
3. le provider **Phone** n'est pas nécessaire ;
4. ne configurez aucun SMS Provider.

Important : ces adresses techniques `@VOTRE-PROJET.supabase.co` ne correspondent pas à une boîte email et ne reçoivent aucun message. La confirmation email doit donc être désactivée.

## Installer le schéma

Dans **SQL Editor**, pour une installation neuve, exécutez dans cet ordre :

1. `supabase/schema.sql`
2. `supabase/patch_v10_business_refactor.sql`
3. `supabase/patch_v10_2_self_validation_tiles_notifications.sql`

`patch_v10_1_tiles_calendar_validation.sql` est conservé uniquement comme historique et ne doit pas être appliqué sur une nouvelle installation V10.2.

Le trigger de création de profil récupère le vrai téléphone depuis `raw_user_meta_data.phone`.

## Lancer Flutter

```powershell
flutter clean
flutter pub get
flutter run -d chrome --dart-define=SUPABASE_URL=https://VOTRE-PROJET.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=VOTRE_CLE_PUBLIQUE
```

Sans les deux `dart-define`, l'application repasse volontairement en mode local.

## Administrateur

Créez d'abord le compte administrateur depuis l'application avec son numéro et son mot de passe, puis exécutez `supabase/promote_admin.sql` après avoir remplacé le numéro.

## Règles métier conservées

- un médecin ne voit que les profils/plannings autorisés de son établissement ;
- l'admin voit l'ensemble du réseau ;
- transfert/échange uniquement entre médecins du même établissement ;
- gardes impliquées dans une demande active verrouillées ;
- destinataire obligé d'accepter/refuser avant décision admin ;
- validation/rejet final réservé à l'admin ;
- échange appliqué transactionnellement ;
- conflits de dates revérifiés côté serveur.

## Limite volontaire

Comme aucun vrai email ni SMS n'est utilisé, **la récupération automatique d'un mot de passe oublié n'est pas encore disponible**. Il faudra prévoir plus tard un flux administrateur de réinitialisation ou un canal de récupération séparé.

Les rappels natifs et les photos **Médecins Séniors de Garde / Astreinte** restent pour l'instant locaux.

## Mise à jour V9.7

Pour une base déjà en V9.5, exécuter une seule fois :

`patch_v9_7_leave_approval_and_admin_delete.sql`

Ce patch est cumulatif et comprend la suppression administrative V9.6. Si vous n'avez pas encore exécuté le patch V9.6, ne l'exécutez pas avant/après celui-ci.

## Mise à jour V10.2 — tuiles et validation définitive par le médecin

Pour une base **déjà migrée en V10** avec `patch_v10_business_refactor.sql`, exécutez une seule fois dans **SQL Editor** :

`patch_v10_2_self_validation_tiles_notifications.sql`

Le patch V10.2 est cumulatif : vous **n'avez pas besoin d'exécuter V10.1**. S'il a déjà été exécuté, V10.2 remplace proprement l'ancien workflow de validation du calendrier par l'administrateur.

Après V10.2 :

- le médecin place lui-même les tuiles **Service Jour/24H/Nuit**, **Urgences Jour/24H/Nuit** et **Congé** ;
- le médecin valide son mois lui-même, de façon irréversible ;
- l'admin ne valide pas le mois complet ;
- l'admin valide les **transferts, échanges et congés** ;
- seul l'admin peut supprimer une affectation déjà validée ;
- les tuiles Congé deviennent automatiquement des demandes admin lors de la validation du mois ;
- les collègues ne voient un congé qu'après son approbation ;
- `medical_grade` (`junior`/`senior`) ne donne aucun droit ; seul `role='admin'` accorde les permissions administratives.

La fonction Edge `send-push` et le secret `FCM_SERVICE_ACCOUNT_JSON` de V10 peuvent rester inchangés pour cette mise à jour.

Si un administrateur doit être Junior, utilisez simplement :

```sql
update public.profiles
set medical_grade='junior', fonction='junior', role='admin'
where phone='+212XXXXXXXXX';
```

Le grade reste Junior ; les droits viennent uniquement de `role='admin'`.

## V11.6.0 — Import automatique des PDF officiels Urgences

Exécuter une seule fois `patch_v11_6_0_official_pdf_auto_import.sql` dans SQL Editor. Aucune Edge Function supplémentaire n'est requise : la lecture du PDF est faite dans GardeFlow avec `pdfrx`, puis l'écriture multi-utilisateurs passe par un RPC `security definer` réservé aux administrateurs.
