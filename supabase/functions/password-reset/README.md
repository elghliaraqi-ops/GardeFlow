# GardeFlow password-reset

Cette Edge Function fournit la récupération de mot de passe par code à 6 chiffres.

Le médecin saisit son numéro dans l'application. Le code n'est jamais envoyé directement au médecin : il est envoyé via Firebase Cloud Messaging aux administrateurs GardeFlow actifs de son établissement, avec le nom et le numéro du demandeur afin que l'administrateur puisse l'identifier puis lui transmettre le code. Si aucun administrateur actif n'est rattaché à cet établissement, les administrateurs réseau actifs servent de secours.

Aucune migration SQL n'est nécessaire. La fonction utilise les tables `profiles` et `push_tokens` déjà présentes, ainsi que le secret `FCM_SERVICE_ACCOUNT_JSON` déjà utilisé par `send-push`.

La fonction doit être publique au niveau de la passerelle Supabase, car l'utilisateur qui a oublié son mot de passe n'a par définition pas de session valide. La sécurité du changement de mot de passe est assurée dans la fonction par un code temporaire stocké dans `app_metadata`, avec expiration et limite de tentatives.

Déploiement :

```bash
supabase functions deploy password-reset --no-verify-jwt
```

Le code expire après 10 minutes, un nouveau code ne peut être généré qu'après 60 secondes et cinq essais incorrects maximum sont acceptés.
