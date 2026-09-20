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
| **Total** | | **188 Ko** |

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
