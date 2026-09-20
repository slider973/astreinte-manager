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
