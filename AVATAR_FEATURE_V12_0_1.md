# Avatars Juniors — GardeFlow V12.0.1

- 6 avatars médecin stylisés intégrés à l’application.
- Choix disponible uniquement pour les médecins Juniors dans **Mon profil → Mon espace → Profil**.
- Option **Aucun** pour revenir aux initiales.
- Le choix est synchronisé via Supabase (`profiles.avatar_key`).
- Les médecins Séniors ne peuvent pas attribuer d’avatar ; un passage Junior → Sénior efface automatiquement la valeur.
- Le même avatar est utilisé sur les surfaces d’identité Junior : profil, en-tête, annuaire, vues administrateur, gestion des comptes, annonces et classement Practice.
- Si aucun avatar n’est choisi ou si le serveur est indisponible, les initiales restent le fallback.
