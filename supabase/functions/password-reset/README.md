# GardeFlow password-reset

Cette Edge Function fournit la récupération de mot de passe par code à 6 chiffres envoyé via Firebase Cloud Messaging à un appareil déjà associé au compte GardeFlow.

Aucune migration SQL n'est nécessaire. Elle utilise les tables `profiles` et `push_tokens` déjà présentes, ainsi que le secret `FCM_SERVICE_ACCOUNT_JSON` déjà utilisé par `send-push`.

La fonction doit être publique au niveau de la passerelle Supabase, car l'utilisateur qui a oublié son mot de passe n'a par définition pas de session valide. La sécurité du changement de mot de passe est assurée dans la fonction par le code temporaire stocké dans `app_metadata`, avec expiration et limite de tentatives.

Déploiement :

```bash
supabase functions deploy password-reset --no-verify-jwt
```

Le code expire après 10 minutes, un nouveau code ne peut être généré qu'après 60 secondes et cinq essais incorrects maximum sont acceptés.
