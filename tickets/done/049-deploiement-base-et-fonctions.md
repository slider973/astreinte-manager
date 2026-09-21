# 049 — Mettre la base et les Edge Functions en ligne avec la PWA

- **Épopée** : E9 Release
- **Priorité** : P0
- **Dépend de** : 032
- **Branche** : `feat/049-deploiement-base-et-fonctions`
- **PR** : —
- **Statut** : terminé le 2026-09-21 (PR créée)

## Contexte

Le 21 septembre 2026, le propriétaire a voulu inviter son premier pompier depuis la production.
L'écran a répondu « Impossible de joindre le serveur. Vérifie ta connexion, puis réessaie. » Son
réseau allait très bien. La vérité était ailleurs : **aucune des onze Edge Functions n'était
déployée sur le projet de production**, et **cinq migrations manquaient** — 0030 à 0034.

Les fonctions rendaient toutes un 404. Invitation, acceptation d'invitation, publication du
planning, envoi de notification, export d'agenda, réattribution, export RGPD, abonnement Stripe :
tout ce qui passe par une fonction était mort en production depuis le premier jour, sans que rien
ne le signale. La table du plafond d'envoi et la colonne de prénom des invitations n'existaient pas
non plus.

Réparé à la main le jour même, par `supabase db push --linked --include-all` puis
`supabase functions deploy`. Ce ticket existe pour que la réparation ne soit plus à refaire.

**La cause est une lacune, pas une panne.** `.github/workflows/deploy.yml` ne met en ligne que la
PWA sur Vercel. Il ne connaît ni `supabase/migrations/`, ni `supabase/functions/`. Chaque PR
fusionnée qui touche la base ou une fonction creuse donc un écart de plus entre le dépôt et la
production, et cet écart ne se voit qu'au moment où quelqu'un s'en sert.

`docs/DEPLOIEMENT.md § 8` connaît deux états, base absente et base présente. Il lui manque le
troisième, celui qu'on a eu : **base présente mais en retard**.

## À faire

### Mettre la base en ligne
Appliquer les migrations en attente sur le projet de production, après une CI verte sur `main`,
comme le fait déjà la mise en ligne de la PWA. Le jeton d'accès Supabase et la référence du projet
sont des secrets GitHub, jamais des valeurs du dépôt.

**Une migration en production ne se joue pas à l'aveugle.** Décider et documenter le garde-fou :
soit un environnement GitHub protégé qui demande une approbation humaine avant d'écrire sur la base
de production, soit une exécution à blanc dont le résultat est lisible avant l'exécution réelle.
Trancher à l'implémentation, et écrire la raison retenue dans le workflow lui-même.

### Mettre les Edge Functions en ligne
Déployer les fonctions dans la même foulée, en respectant les `verify_jwt` de
`supabase/config.toml`. Ne déployer que ce qui a changé si le temps de mise en ligne le demande,
mais ne jamais laisser une fonction en retard sur la base dont elle dépend.

### Ordonner les trois mises en ligne
La base d'abord, les fonctions ensuite, la PWA en dernier. Une fonction qui appelle une procédure
que la base n'a pas encore ne rend pas un message clair, elle rend une erreur de serveur. L'ordre
inverse casse la production pendant quelques minutes à chaque déploiement.

### Dire quand la production est en retard
Le défaut a vécu tant que personne ne s'en est servi, parce que rien ne le disait. Ajouter une vérification qui compare les
migrations du dépôt à celles de la production et les fonctions attendues à celles déployées, et qui
échoue bruyamment en cas d'écart. Elle tourne à la mise en ligne, et elle doit pouvoir être lancée
à la demande pour répondre à la question « est-ce que la production est à jour ? ».

### La configuration de l'authentification n'est reproductible nulle part
Découvert le 21 septembre 2026, en cherchant pourquoi une invitation acceptée renvoyait sur
« Aucune caserne ». La production servait le gabarit de courriel **par défaut de Supabase**, en
anglais, qui envoie un lien de connexion là où l'application attend un code à six chiffres. Ouvrir
ce lien change de page, le jeton d'invitation vit en mémoire seulement, il est donc perdu, et
l'invitation ne peut plus être acceptée. Le gabarit français existe pourtant dans le dépôt depuis le
ticket 001, à `supabase/templates/magic_link.html`, et `supabase/config.toml` le déclare.

Rien ne le posait en production, parce que rien ne pose la configuration d'authentification en
production. Quatre réglages étaient dans ce cas, tous corrigés à la main le jour même :

- le gabarit et le sujet du courriel de connexion ;
- le serveur d'envoi, resté celui de Supabase, ce qui interdisait le gabarit personnalisé ;
- le plafond d'envoi, resté à deux courriels par heure, la valeur du plan gratuit ;
- les adresses de redirection autorisées, qui ignoraient le domaine propre de l'application.

Ce sont les mêmes symptômes que les Edge Functions absentes : le dépôt sait, la production ignore,
et personne ne l'apprend avant qu'un pompier reste à la porte. `supabase/config.toml` décrit déjà
tout cela pour la pile locale ; il faut que la production le reçoive.

### Le répartiteur de notifications visait la pile locale
Découvert le 21 septembre 2026, après « les notifications ne marchent pas ». Le secret Vault
`notify_function_url`, créé par la migration 0014 avec l'adresse Docker de la pile locale, n'avait
jamais été remplacé en production. Toutes les minutes, `cron_dispatch_notifications` s'exécutait
avec succès, poussait une requête `pg_net` vers un hôte inexistant, et la file restait en attente,
tentatives comptées, sans qu'aucune notification ne parte. `supabase/functions/README.md`
documente la commande à passer une fois ; personne ne l'avait passée, et rien ne le signalait.

Même famille que les trois précédents. La mise en ligne doit poser cette adresse, ou la
vérification d'écart doit refuser une file qui échoue sur résolution de nom.

### Le jeton Vercel
Le jeton actuellement posé en secret est lié au projet et non au compte : la ligne de commande
Vercel répond « User not found ». La mise en ligne de la PWA échoue donc, et le déploiement se fait
à la main par l'API. Poser un jeton de compte, depuis les réglages personnels de Vercel, et vérifier
que le workflow passe.

### Mettre à jour la documentation
`docs/DEPLOIEMENT.md` gagne le troisième état, base en retard, avec ce qu'il donne à l'écran et
comment le rattraper. La procédure manuelle de secours y figure aussi : c'est elle qui a sauvé la
journée du 21 septembre.

## Critères d'acceptation

- Une PR fusionnée sur `main` qui ajoute une migration la voit appliquée en production sans
  intervention manuelle, dans le garde-fou retenu.
- Une PR fusionnée qui modifie une Edge Function la voit déployée en production.
- La base est mise en ligne avant les fonctions, et les fonctions avant la PWA.
- Un écart entre le dépôt et la production est signalé par un échec, pas découvert par un 404.
- La mise en ligne de la PWA par le workflow réussit, sans passer par l'API à la main.
- Aucun jeton ni mot de passe n'apparaît dans le dépôt, et l'analyse de secrets passe.
- L'adresse de la fonction de notification dans Vault vise le projet hébergé, et la mise en
  ligne la pose.
- La configuration d'authentification de la production est posée depuis le dépôt : gabarits de
  courriel, serveur d'envoi, plafonds, adresses de redirection.
- `docs/DEPLOIEMENT.md` décrit les trois états et la procédure de secours.
