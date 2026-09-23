# Le parcours complet — ce qui tourne, où, et pourquoi

Ticket 035. Un mois d'astreintes suivi d'un bout à l'autre : l'administrateur invite,
la recrue accepte, elle saisit son mois, l'administrateur construit le planning et le
publie, la recrue refuse un créneau et en accepte un autre, l'administrateur réattribue,
le second pompier accepte, le planning se valide tout seul.

Le parcours existe en **deux exemplaires**, qui suivent le même fil par deux côtés :

| Fichier | Ce qu'il éprouve | Où il tourne | Durée mesurée |
|---|---|---|---|
| `test/parcours/parcours_complet_test.dart` | les écrans, l'état, la navigation | tâche CI « parcours », Chrome sans interface | ~20 s (compilation comprise) |
| `supabase/tests/parcours_complet_test.sql` | la base : RLS, fonctions, tâches planifiées | tâche CI « base-donnees », via `scripts/test_rls.sh` | ~16 s pour toute la suite |

Aucun des deux ne joue les deux moitiés à la fois, et c'est la seule chose que ce
document a vraiment à dire. La raison est dans la CI : la tâche « base-donnees »
démarre une pile Supabase **réduite** — Postgres et GoTrue, sans `kong`, sans
`postgrest`, sans `edge-runtime` — parce que les images manquantes pèsent plus de
quatre gigaoctets à télécharger et feraient sauter le budget de dix minutes du ticket
003. Une application Flutter qui parlerait à cette pile n'aurait ni API REST ni Edge
Functions à joindre : le parcours « vrai » de bout en bout n'y est pas jouable.

Plutôt que de livrer un test qui échoue au hasard, le fil est coupé en deux à un
endroit net — la frontière du dépôt de données — et les deux moitiés sont jouées
chacune contre son vrai moteur.

## Le parcours Dart

```
flutter test --platform chrome test/parcours     # Chrome sans interface
flutter test test/parcours                       # la même chose, sur la VM Dart
```

C'est du vrai Chrome : le même moteur, le même JavaScript compilé, le même arbre de
widgets que la PWA. Le pilotage se fait **par l'arbre**, jamais par les pixels.
`WidgetTester` tourne dans la page et `tester.tap(find.text(…))` touche le widget ;
un pilote extérieur, lui, viserait une coordonnée sur un canevas, et les nœuds
d'accessibilité de Flutter web n'acceptent pas toujours un clic programmatique. C'est
le mur sur lequel plusieurs tentatives ont buté au fil du projet.

Le paquet `integration_test` n'est pas utilisé, et ce n'est pas un oubli :

```
$ flutter test -d chrome test/parcours/parcours_complet_test.dart
Web devices are not supported for integration tests yet.
```

Sur Flutter 3.38, le seul chemin vers un navigateur est `--platform chrome`. Le
répertoire s'appelle donc `test/parcours/` et non `integration_test/` : ce nom-là fait
basculer `flutter test` vers le chemin « appareil », qui refuse le web.

Effet de bord utile : `flutter test` sans argument joue aussi le parcours, sur la VM,
dans la tâche « flutter ». Il est donc gardé deux fois, pour cinq secondes de plus.

### `--wasm` ne joue pas ce parcours

Depuis le ticket 065, la production est servie en WebAssembly. La tentation est d'aligner
le parcours : `flutter test --platform chrome --wasm test/parcours`. Elle ne tient pas.

**La commande compile le module Wasm, puis n'exécute aucun test.** Ce qui se passe ensuite
dépend de l'état du cache de compilation, et les deux issues ont été observées, sur deux
machines :

- elle s'arrête sur `00:00 +0: loading …/parcours_complet_test.dart`, annonce
  « No tests ran. » et **rend 0** ;
- ou elle reste sur cette même ligne sans jamais rendre la main (tuée à 13 minutes).

L'une passerait pour un succès, l'autre bloquerait la CI jusqu'au `timeout-minutes`. Deux
raisons de ne pas la mettre en CI, et aucune de s'y fier. La tâche « parcours » reste donc
sur `--platform chrome` — dart2js —, et le moteur Wasm est éprouvé là où il vit, dans un
vrai navigateur sur la construction de production (`docs/DEPLOIEMENT.md` § 6 bis).

Ce n'est pas une perte de couverture : `flutter build web --wasm`, joué par la CI,
passe le code dans **les deux** compilateurs. Ce que `--platform chrome` vérifie ici,
c'est le fil des écrans, pas le rastériseur.

### Le serveur du parcours

`backend_memoire.dart` est une caserne en mémoire qui rejoue les règles de la base —
unicité des attributions actives, `was_available` posé par la base, `proposed_at` posé
à la publication, complétude en attributions **acceptées**, `replaced_by` sur le plus
ancien trou non couvert. Chaque règle porte en commentaire le numéro de la migration
dont elle vient.

Ce qu'elle ne rejoue pas est dit une fois, en tête du fichier : la RLS. La prétendre
en Dart donnerait une seconde vérité à tenir, et c'est le parcours SQL qui l'éprouve.

## Le parcours SQL

```
scripts/test_rls.sh                              # avec une base locale démarrée
psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/parcours_complet_test.sql
```

Les mêmes onze étapes, jouées **acteur par acteur** : chaque écriture passe par
`set local role authenticated` et les claims JWT de la personne concernée, comme
PostgREST le ferait. Le brouillon reste invisible des pompiers, la période verrouillée
refuse la saisie en filtrant sans lever, la validation automatique bascule le planning
et notifie les trois membres actifs.

Deux tâches planifiées sont jouées **dans le fil**, avec une date de référence :
`cron_lock_periods` une heure après la date limite, `cron_assignment_reminders`
vingt-cinq heures après la publication. Ce ne sont pas des figurants : c'est le
verrouillage qui ferme la saisie, et c'est la relance qui va chercher la réponse du
second pompier. Leur comportement fin reste éprouvé par `periods_cron_test.sql` et
`assignment_reminders_test.sql`.

## Ce qui reste hors CI

- **La couche HTTP des Edge Functions.** `invite-member`, `accept-invitation`,
  `publish-schedule` et `reassign-shift` emballent les fonctions SQL appelées par le
  parcours SQL. Leur logique de décision vit dans des modules purs (`_shared/`), testés
  par la tâche « edge-functions » ; leur couche HTTP demande `supabase functions serve`
  et se joue à la main avec `scripts/test_functions.sh` avant de pousser.
- **Le parcours contre un vrai Supabase.** Il se joue localement, avec la pile complète
  (`supabase start`, `flutter run -d chrome --dart-define-from-file=env/dev.json`), et
  reste une vérification humaine : la CI n'a ni les images ni le budget pour lui.
- **La PWA installée sur un téléphone.** Les gestes qui ne se simulent pas — la
  peinture au doigt sur la grille du mois, une notification reçue écran éteint —
  demandent un appareil.
