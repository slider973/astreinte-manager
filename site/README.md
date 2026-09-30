# Site vitrine astreinte-sp.fr

Ticket 075. Brief : `design/075-site-vitrine.md` (structure, textes, choix visuels). Mise en
ligne et DNS : `docs/DEPLOIEMENT.md` § 11.

**HTML et CSS écrits à la main, sans construction.** `public/` est servi tel quel par Vercel :
ce qui est relu en revue est ce qui part en ligne. Pas de Node, pas de `package.json`, pas de
Flutter.

```
site/
├── public/              ce qui est servi — rien d'autre n'y va
│   ├── index.html       accueil
│   ├── mentions-legales.html, confidentialite.html, 404.html
│   ├── style.v1.css     feuille unique ; print.v1.css pour l'impression
│   ├── fonts/           WOFF2 sous-ensemblés + OFL.txt
│   ├── images/          captures AVIF/WebP, icône, image de partage
│   ├── favicon.svg, favicon.ico, apple-touch-icon.png, robots.txt, sitemap.xml
├── sources/
│   ├── captures/        les quatre captures PNG sans perte, source des images servies
│   ├── partage.html     source de l'image de partage (1200 × 630)
│   └── planning-captures.sql  le planning fictif des captures (base locale seulement)
├── scripts/
│   ├── verifier.py      contrôles de la CI (liens, tiers, poids, pied de page, CSP, marques)
│   ├── servir.py        serveur local qui imite Vercel (cleanUrls, 404, en-têtes)
│   ├── images.sh        PNG → AVIF/WebP 1x et 2x
│   └── partage.sh       rend l'image de partage avec Chrome
├── vercel.json          en-têtes (CSP, cache), cleanUrls ; envoyé à la racine du déploiement
└── .htmlvalidate.json   règles de html-validate
```

## Relire en local

```sh
python3 site/scripts/servir.py --port 8080      # http://127.0.0.1:8080/
python3 site/scripts/verifier.py --lister-marqueurs
(cd site && npx --yes html-validate@11.16.1 public/*.html)   # Node ≥ 22.22
```

Ce sont les deux commandes de la tâche « site » de `.github/workflows/ci.yml`. La mise en ligne
ajoute `verifier.py --marqueurs`, qui **échoue** tant qu'une marque `[À COMPLÉTER` reste dans
une page : des mentions légales trouées ne se publient pas.

## Règles à tenir

- **Le pied de page est identique sur les quatre pages**, au caractère près. En changer un, c'est
  changer les quatre ; `verifier.py` le contrôle.
- **Le script en ligne** (contact assemblé au clic, tampon « Accepté ») est le même sur les
  quatre pages. Son empreinte `sha256` est dans la CSP de `vercel.json`. Après toute modification,
  recalculer :
  ```sh
  python3 -c "import re,hashlib,base64;s=open('site/public/index.html').read();m=re.search(r'<script>(.*?)</script>',s,re.S).group(1);print('sha256-'+base64.b64encode(hashlib.sha256(m.encode()).digest()).decode())"
  ```
  et remplacer l'ancienne dans `vercel.json`. `verifier.py` échoue tant que les deux divergent.
- **L'adresse de contact n'est jamais écrite en clair** : les liens portent `href="#contact"` et
  `data-courriel="essai|plus60|contact"`, le script assemble le `mailto:` au clic. Sans
  JavaScript, `#contact` mène à la ligne du pied de page qui l'explique.
- **Aucune ressource chez un tiers** : fontes, images, feuilles, tout vient de `public/`. La CSP
  (`default-src 'none'`) le garantit en production, `verifier.py` le vérifie avant.
- **Cache** : `fonts/` et `style.vN.css` / `print.vN.css` sont servis `immutable` pendant un an.
  Modifier une feuille, c'est la renommer (`style.v2.css`) et changer les quatre pages. Les images
  sont gardées une semaine.
- **Les prix** (55 € / 550 €) sont ceux de l'écran Abonnement en production
  (`docs/STRIPE.md` § 5). Changer l'un, c'est changer l'autre dans la même PR.

## Les captures

Quatre captures réelles de la PWA, **données fictives seulement** (seed local, jamais la
production). Produites le 30 septembre 2026 :

1. `supabase db reset` (seed : CIS Saint-Martin, membres fictifs) ;
2. un planning d'octobre créé et publié par SQL sur la base locale (`create_schedule`,
   `apply_auto_proposal`, `publish_schedule`), la plupart des créneaux passés en acceptés, deux
   laissés proposés à Marie Lefebvre (`membre1@caserne-a.test`) ;
3. PWA construite avec `env/dev.json`, pilotée dans Chrome sans fenêtre, thème clair :
   téléphone 390 × 844 à 2x (A accueil, C saisie de novembre, D proposition ouverte), ordinateur
   1440 × 900 à 2x (B matrice de l'admin).

Vérifier sur chaque nouvelle capture qu'aucune adresse électronique, aucun numéro de téléphone et
aucune caserne réelle n'apparaît. Puis :

```sh
site/scripts/images.sh      # sources/captures/*.png → public/images/*.avif|webp (magick, avifenc, cwebp)
site/scripts/partage.sh     # sources/partage.html → public/images/partage.png (Chrome)
python3 site/scripts/verifier.py   # budgets
```

Le recadrage de la matrice pour les écrans étroits garde **cinq jours** et non dix comme le
brief le proposait : à 350 px de large, dix jours rendaient noms et cases illisibles.

## Les fontes

Archivo (titres) et Atkinson Hyperlegible Next et Mono (texte, chiffres), les fontes de l'app,
licence SIL OFL 1.1 (`public/fonts/OFL.txt`). Sous-ensemblées en WOFF2 depuis les instances
statiques de `assets/fonts/` :

```sh
python3 -m venv /tmp/ft && /tmp/ft/bin/pip install fonttools brotli
TXT='U+0020-007E,U+00A0-00FF,U+0152-0153,U+0178,U+2009,U+2011,U+2013-2014,U+2018-2019,U+201C-201E,U+2022,U+2026,U+202F,U+2039-203A,U+20AC,U+2264-2265'
MONO='U+0020,U+0030-0039,U+002C-002E,U+0025,U+002B,U+003A,U+00A0,U+2009,U+202F,U+20AC'
f() { /tmp/ft/bin/pyftsubset "assets/fonts/$1" --unicodes="$3" \
  --layout-features='kern,liga,tnum,lnum,case' --flavor=woff2 --no-hinting --desubroutinize \
  --output-file="site/public/fonts/$2"; }
f Archivo-Bold.ttf archivo-700.woff2 "$TXT"
f Archivo-SemiBold.ttf archivo-600.woff2 "$TXT"
f AtkinsonHyperlegibleNext-Regular.ttf atkinson-next-400.woff2 "$TXT"
f AtkinsonHyperlegibleNext-Bold.ttf atkinson-next-700.woff2 "$TXT"
f AtkinsonHyperlegibleMono-Bold.ttf atkinson-mono-700.woff2 "$MONO"
```

Contrairement à l'app, le WOFF2 convient ici : c'est le navigateur qui décode, pas Skia. Les
replis (`Archivo repli`, `Atkinson repli`) sont réglés sur les métriques mesurées avec fontTools
(`size-adjust`, `ascent-override`…) pour que la page ne saute pas au chargement.
