# 065 — Un défilement fluide sur la PWA installée

- **Épopée** : E9 Release
- **Priorité** : P1
- **Dépend de** : 060
- **Branche** : `feat/065-fluidite-defilement-pwa`
- **PR** : —
- **Statut** : à faire

## Contexte

Signalé par le propriétaire le 23 septembre 2026, sur un iPhone 17 Pro Max avec la PWA
installée : « le scroll saccade ».

Ce que la construction actuelle explique (`scripts/build_web.sh`, `vercel.json`) :

- La PWA est livrée en **CanvasKit compilé en JavaScript**, sur un seul fil. Flutter web ne
  délègue pas le défilement au navigateur : chaque image est dessinée par le moteur sur le fil
  principal. Sur téléphone, cela donne un à-coup au premier défilement d'un écran (compilation
  des shaders), des images perdues sur les écrans denses (le calendrier de saisie et ses cases
  peintes, la matrice admin à 3 720 cases) et une inertie qui n'est pas celle du système.
- **Aucun build WebAssembly n'est livré**, alors que la CI note à chaque build « Wasm dry run
  succeeded » : le code compile déjà en Wasm. Avec `flutter build web --wasm`, le rendu passe par
  Skwasm, **multi-fil**, à condition de servir deux en-têtes d'isolation
  (`Cross-Origin-Opener-Policy: same-origin`, `Cross-Origin-Embedder-Policy: require-corp` ou
  `credentialless`). Les navigateurs sans WasmGC retombent seuls sur CanvasKit JS ; Safari le
  supporte depuis 18.2, donc l'iPhone du propriétaire en bénéficie.
- Un plafond qui ne dépend pas de nous : sur un iPhone ProMotion, Safari cadence
  `requestAnimationFrame` à 60 Hz par défaut, là où le reste du téléphone défile à 120 Hz. Une
  PWA Flutter y paraîtra toujours moins fluide qu'une liste native, même sans image perdue. Le
  ticket doit le dire au propriétaire, pas le lui promettre.

## À faire

1. **Mesurer avant de changer.** Un build de production local, servi avec les en-têtes,
   ouvert sur Chrome et sur Safari de bureau : overlay de performance de Flutter
   (`--profile`), trace des images sur trois écrans — Accueil, Calendrier (mois saisi à moitié),
   matrice admin (soixante membres) — en défilement, avec le nombre d'images perdues. Les
   chiffres vont dans le corps de la PR, avant et après.
2. **Livrer le build Wasm avec repli.** `scripts/build_web.sh` construit avec `--wasm` ; les
   deux en-têtes d'isolation sont ajoutés à `vercel.json` ; `scripts/verifier_production.sh`
   vérifie qu'ils sont servis et que `main.dart.wasm` (ou l'équivalent) est présent ; le repli
   CanvasKit JS reste fonctionnel (vérifier avec un navigateur sans WasmGC ou en le désactivant).
   Vérifier que les appels à Supabase, Resend et Firebase ne sont pas bloqués par
   `require-corp` ; si une ressource tierce l'est, passer à `credentialless` et le documenter
   dans `docs/DEPLOIEMENT.md`.
3. **Les deux écrans denses.** `RepaintBoundary` par ligne dans la grille du calendrier et dans
   la matrice, aucune `Opacity` animée pendant le défilement, listes en `builder` partout où
   elles ne le sont pas. Une correction seulement si la mesure de l'étape 1 la justifie.
4. **Le premier défilement.** Vérifier si le préchauffage des shaders de Skwasm rend l'à-coup
   initial imperceptible ; sinon, le consigner.
5. `docs/DEPLOIEMENT.md` : le moteur de rendu, les en-têtes, le repli, et la note sur le
   plafond de 60 Hz de Safari sur ProMotion.

## Critères d'acceptation

- La production sert un build Wasm avec les en-têtes d'isolation ; un navigateur sans WasmGC
  charge toujours l'application.
- Le déploiement automatique (tickets 049, 054, 060) reste vert sur les cinq travaux, et
  `scripts/verifier_production.sh` vérifie les en-têtes.
- Sur Chrome de bureau, les traces avant / après sur les trois écrans montrent moins d'images
  perdues en défilement ; les chiffres sont dans la PR.
- Aucun appel réseau de l'application n'est bloqué par les en-têtes ; connexion par code,
  saisie, réponse à une proposition, notifications : parcours de bout en bout verts.
- `flutter analyze` sans avertissement, `flutter test` verts, `flutter build web --wasm` qui
  passe, détecteur Impeccable à vide.
- Le propriétaire vérifie sur son iPhone 17 Pro Max, PWA réinstallée ; le ticket dit en clair
  ce que le plafond de Safari laisse hors de portée.
