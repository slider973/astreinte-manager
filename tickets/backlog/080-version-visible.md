# 080 — Afficher la version pour distinguer ce qui est déployé

- **Épopée** : E1 Socle
- **Priorité** : P1
- **Branche** : `feat/080-version-visible`
- **Statut** : backlog

## Le besoin, dans les mots du propriétaire

> « est-ce que tu peux rajouter un numéro de version quelque part que je puisse identifier
> les différentes versions »

Il teste la PWA après chaque correctif et ne peut pas savoir **ce qu'il a sous les yeux**.
Un service worker sert parfois l'ancienne version depuis le cache : sans repère affiché,
un correctif qui marche et un correctif pas encore arrivé sont indiscernables. Il a
signalé trois défauts aujourd'hui et doit vérifier trois correctifs — sans version visible,
chaque vérification est un doute.

## Constat

1. **`pubspec.yaml` est resté à `version: 0.1.0+1`** depuis le premier jour. Aucune des
   79 livraisons ne l'a fait bouger : le numéro ne veut rien dire.

2. **Rien n'affiche de version dans l'app.** Aucune trace de `package_info_plus`,
   `appVersion` ou `buildNumber` dans `lib/` — et le paquet n'est pas une dépendance.

3. **Aucune section « À propos »** dans l'écran de profil ni dans les réglages.

4. Le vrai identifiant de ce qui tourne est **l'empreinte du commit** : `deploy.yml` part
   d'un `workflow_run` sur `main`, chaque déploiement correspond donc à un commit précis.
   `scripts/build_web.sh` vérifie déjà l'empreinte de `main.dart.js` après mise en ligne —
   la notion de « ce qui est servi » existe, elle n'est simplement pas montrée.

## Décision

Afficher **le commit court et la date de construction**, pas un numéro sémantique.

Un `0.1.0+1` que personne ne fait avancer mentirait ; une version sémantique obligerait à
décider à chaque ticket si c'est un `patch` ou un `minor`, pour une PWA qui n'a ni store ni
installation versionnée. Le commit court (`4da5f88`) est **exact, automatique et
vérifiable** : il se compare à `git log` et à la liste des PR.

La date de construction répond à la question réellement posée — « est-ce que mon correctif
est en ligne ? » — sans rien connaître de git.

## Ce qu'il faut faire

1. `scripts/build_web.sh` passe deux `--dart-define` : `APP_COMMIT` (sortie de
   `git rev-parse --short HEAD`) et `APP_BUILD_DATE` (ISO 8601, UTC). Valeurs de repli
   explicites (`local`) quand git est absent : une construction locale ne doit pas échouer.

2. Un `lib/core/version/version_app.dart` qui lit ces deux `String.fromEnvironment` —
   `const`, donc figées à la compilation, aucun paquet ajouté, rien au démarrage.

3. Un bloc « À propos » en bas de l'écran de profil, sous `BlocCompte` : la version, la
   date, et l'environnement (`APP_ENV`) quand ce n'est pas la production. **Sélectionnable**
   pour qu'il puisse la recopier dans un message.

4. Les textes dans `AppStrings`, jamais en dur.

## Critères d'acceptation

- [ ] `scripts/build_web.sh` injecte `APP_COMMIT` et `APP_BUILD_DATE` ; une construction
      hors dépôt git donne `local` au lieu d'échouer.
- [ ] L'écran de profil montre un bloc « À propos » avec le commit et la date.
- [ ] L'environnement n'apparaît que hors production (`APP_ENV != prod`) : inutile de dire
      « production » à un pompier.
- [ ] Le texte est sélectionnable.
- [ ] Un test vérifie la présence du bloc et le repli `local` quand rien n'est injecté.
- [ ] `flutter analyze` sans avertissement, `flutter test` verts, `flutter build web` passe.

## Hors périmètre

- Faire avancer `pubspec.yaml` : séparé, et discutable (voir « Décision »).
- Un écran « À propos » dédié : un bloc suffit, l'écran de profil est déjà le lieu des
  réglages.
- Alerter l'utilisateur qu'une nouvelle version existe (rechargement du service worker) :
  un autre besoin, un autre ticket.
