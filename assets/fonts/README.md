# Polices embarquées

**Atkinson Hyperlegible Next** (texte) et **Atkinson Hyperlegible Mono** (nombres), dessinées par
le Braille Institute of America pour maximiser la distinction entre caractères en basse vision.
Licence SIL Open Font License 1.1 (`OFL.txt`).

Source : dépôt officiel Google Fonts, `ofl/atkinsonhyperlegiblenext` et `ofl/atkinsonhyperlegiblemono`
(fichiers variables `AtkinsonHyperlegibleNext[wght].ttf` et `AtkinsonHyperlegibleMono[wght].ttf`,
axe `wght` 200–800).

Les fichiers versionnés ici sont des **instances statiques sous-ensemblées** produites avec
`fontTools` pour ne garder que les graisses et les caractères utilisés par l'application :

```
fonttools varLib.instancer <variable>.ttf wght=<400|600|700>
fonttools subset <instance>.ttf --unicodes=U+0000-00FF,U+0100-017F,… --layout-features='*'

# Le dernier recours du moteur (ticket 037) : le minimum qui rende la famille valide.
pyftsubset AtkinsonHyperlegibleNext-Regular.ttf \
  --unicodes='U+0020-007E,U+00A0,U+00E0,U+00E2,U+00E7,U+00E8,U+00E9,U+00EA,U+00EB,U+00EE,U+00EF,U+00F4,U+00F9,U+00FB,U+00FC,U+FFFD' \
  --layout-features='' --no-hinting --desubroutinize \
  --output-file=AtkinsonHyperlegibleNext-Repli.ttf
```

Jeu de caractères conservé : latin de base, latin étendu A, diacritiques français, guillemets
français, tirets cadratins, puces, flèches, `€`, `∞`, `≤`, `≥`, espaces insécables. 323 glyphes par
fichier, aucun caractère manquant sur le français.

| Fichier | Graisse | Poids |
|---|---|---|
| `AtkinsonHyperlegibleNext-Regular.ttf` | 400 | 42 Ko |
| `AtkinsonHyperlegibleNext-SemiBold.ttf` | 600 | 42 Ko |
| `AtkinsonHyperlegibleNext-Bold.ttf` | 700 | 42 Ko |
| `AtkinsonHyperlegibleMono-SemiBold.ttf` | 600 | 30 Ko |
| `AtkinsonHyperlegibleMono-Bold.ttf` | 700 | 30 Ko |
| `AtkinsonHyperlegibleNext-Repli.ttf` | 400 | 10 Ko |
| **Total** | | **198 Ko** |

`…-Repli.ttf` n'est affiché par aucun écran. C'est le **dernier recours du moteur web**, celui que
CanvasKit exige pour ne pas planter sur du texte dont la famille n'est pas enregistrée, et qu'il
nomme `Roboto`. Tant qu'aucune famille de ce nom n'est déclarée dans `pubspec.yaml`, le moteur la
télécharge chez Google à chaque démarrage (voir ci-dessous). Le fichier est donc le plus petit
sous-ensemble utile — ASCII imprimable, diacritiques français, caractère de substitution, soit 117
glyphes — parce qu'il ne sert qu'à exister. Un renvoi vers la régulière déjà embarquée aurait
marché aussi, mais le moteur télécharge **une fois par famille** : deux familles sur la même
adresse font deux requêtes simultanées, 18 Ko de plus (mesuré au ticket 037).

Les italiques ne sont pas embarquées : `DESIGN.md § Typography` interdit l'italique comme moyen
de hiérarchie. Les graisses 200, 300, 500 et 800 ne le sont pas non plus : l'échelle
typographique n'utilise que 400, 600 et 700.

## Pourquoi pas de WOFF2

Essayé et mesuré au ticket 004. Les cinq fichiers en WOFF2 pèsent 72 Ko au lieu de 184, mais
**Flutter web ne sait pas les décoder** : le moteur remet les octets à Skia, dont le gestionnaire de
fontes ne lit que du `sfnt` (TTF, OTF). Au navigateur, les WOFF2 se téléchargent (200), échouent
silencieusement au décodage, et l'application retombe sur un **Roboto téléchargé depuis
`fonts.gstatic.com`** — la dépendance réseau que ces fichiers embarqués servent justement à éviter.

Le levier correct est la compression de transport : TTF + brotli donne 83 Ko, soit 11 Ko de plus
que le WOFF2, sans rien casser. Exigence d'hébergement : servir ce répertoire avec
`Content-Encoding: br`.

**Fait au ticket 032**, et mesuré à 88 Ko pour les six fichiers. `scripts/build_web.sh` les
compresse sur place après `flutter build web`, et `vercel.json` pose l'en-tête sur
`/assets/assets/fonts/(.*).ttf`. Les deux vont ensemble : servir ces fichiers **sans** l'en-tête
donne des polices illisibles et un repli silencieux sur Roboto — exactement la panne décrite
ci-dessus. Le workflow de déploiement le vérifie après chaque mise en ligne et échoue si l'en-tête
manque (`docs/DEPLOIEMENT.md § 6`).

## Ce qui ne se télécharge plus (ticket 037)

Deux requêtes partaient encore chez Google malgré ces fichiers embarqués. Elles ne partent plus :

- **Roboto** (63 Ko, à chaque ouverture) — le dernier recours inconditionnel du moteur, supprimé en
  déclarant une famille `Roboto` dans `pubspec.yaml` (voir `…-Repli.ttf` ci-dessus) ;
- **les polices Noto** d'un glyphe absent du sous-ensemble — un emoji dans un commentaire, un nom
  en cyrillique. Elles ne partaient pas au démarrage mais **pendant la navigation**, sur du texte
  saisi par les utilisateurs. `fontFallbackBaseUrl` est pointé sur un répertoire à nous qui ne
  contient rien : la requête échoue chez nous et le glyphe s'affiche en caractère de substitution.
  Le raisonnement est dans `web/polices-de-repli/README.md`.

Élargir le sous-ensemble ci-dessus est la bonne réponse à un besoin d'alphabet supplémentaire. Pas
de rouvrir `fonts.gstatic.com`.
