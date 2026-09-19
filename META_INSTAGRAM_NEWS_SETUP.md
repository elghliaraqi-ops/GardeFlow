# GardeFlow — Flux « Actualités du jour »

## Sources
Le flux d'accueil utilise uniquement ces comptes Instagram :
- `ami_um6` — AMI UM6
- `um6ss` — UM6SS
- `huim6bouskoura` — HUIM6 Bouskoura
- `huim6rabat` — HUIM6 Rabat
- `hopital.cheikh.khalifa` — Hôpital Cheikh Khalifa

## Architecture
- Les sources sont enregistrées dans `public.daily_news_sources`.
- Les publications mises en cache sont enregistrées dans `public.daily_news_posts`.
- Les images sont copiées dans le bucket public `daily-news-media`.
- La fonction Edge `sync-instagram-news` interroge l'API Instagram/Meta et alimente le cache.
- Le job `gardeflow-daily-news-sync` lance une synchronisation toutes les 30 minutes.
- L'application lit uniquement le cache Supabase ; aucun jeton Meta n'est embarqué dans l'APK.

## Secrets serveur nécessaires
Configurer dans les secrets des Edge Functions Supabase :
- `META_ACCESS_TOKEN` : jeton Meta valide disposant des autorisations nécessaires à Instagram Business Discovery.
- `META_IG_USER_ID` : identifiant du compte Instagram professionnel connecté utilisé comme compte demandeur.
- `META_GRAPH_VERSION` : optionnel ; permet de choisir explicitement la version Graph API.

Tant que les deux premiers secrets ne sont pas configurés, la fonction renvoie `missing_credentials` et l'application affiche les raccourcis vers les cinq sources sans inventer de publications.

## Sécurité
Le jeton Meta doit rester côté serveur. Il ne doit jamais être ajouté à Flutter, au dépôt GitHub ou à une constante publique.
