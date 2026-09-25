# Cadence v1 : mise en ligne

Fichiers à déposer ensemble : `index.html`, `manifest.webmanifest`, `sw.js`, `icon.svg`, `icon-192.png`, `icon-512.png`. Le fichier `schema.sql` sert uniquement à préparer la base.

## 1. Tester tout de suite, sans base
Ouvre `index.html` dans un navigateur et choisis « Essayer sans compte (mode démo) ». Les données restent dans ce navigateur, sans partage.

## 2. Créer la base Supabase (10 minutes)
1. Sur supabase.com, crée un **nouveau projet dédié** (ne réutilise pas celui de Spoties). Région : Europe (Paris ou Francfort).
2. SQL Editor > New query > colle tout `schema.sql` > Run. Tu dois obtenir « Success ».
3. Authentication > URL Configuration : mets l'adresse GitHub Pages de l'app dans **Site URL** (sinon les liens de confirmation et de mot de passe renvoient vers localhost).
4. Authentication > Sign In / Providers > Email : garde « Confirm email » activé pour la classe. Tu peux le couper le temps de tes propres tests.
5. Project Settings > API : copie **Project URL** et la clé **anon public**.

## 3. Brancher l'app
En haut du script de `index.html`, remplis :
```js
const CONFIG = {
  SUPABASE_URL: 'https://xxxx.supabase.co',
  SUPABASE_ANON_KEY: 'eyJhbGciOi...'
};
```
La clé anon est faite pour être publique : la sécurité repose sur les règles RLS du schéma. Ne mets **jamais** la clé `service_role` dans l'app.

## 4. Publier sur GitHub Pages
Nouveau dépôt > dépose les 6 fichiers de l'app > Settings > Pages > Branch `main`, dossier `/ (root)` > Save. L'adresse apparaît après une minute.

## 5. Installer sur téléphone
iPhone : Safari > Partager > « Sur l'écran d'accueil ». Android : Chrome > menu > « Installer l'application ».

## 6. Inviter la classe
Crée un espace d'équipe (sélecteur d'espace > Créer un espace d'équipe, planning d'alternance coché), puis partage le code d'invitation affiché dans les réglages de l'espace.

## À savoir
- Offre gratuite Supabase : le projet se met en pause après une semaine sans activité. Il se relance depuis le tableau de bord.
- Chaque inscription crée automatiquement un profil et un espace personnel « Mon calendrier ».
- Rôles : propriétaire (gère l'espace), éditeur (crée et modifie), lecteur (consulte).
- Pour une mise à jour de l'app, change `CACHE` dans `sw.js` (ex. `cadence-v1.0.1`) pour forcer le rafraîchissement sur les téléphones.
