# Relance des compilations Viscéral × Radio — 09/10/2026

Ce fichier documente la demande de recompilation du module Viscéral × Radio après fusion du correctif Groq JSON strict.

- Branche de référence : `main`.
- Périmètre : Web (publication Pages), Android APK, iOS unsigned.
- Backend existant : Supabase Edge Function `generate-visceral-radio`, version 2 active.
- Aucune modification fonctionnelle requise pour cette relance.

Les workflows de compilation écoutent `source/**` : la création de ce fichier déclenche les builds sur `main`.
