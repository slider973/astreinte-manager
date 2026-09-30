# 075 — Le site vitrine astreinte-sp.fr

- **Épopée** : E9 Release
- **Priorité** : P1
- **Dépend de** : —
- **Branche** : `feat/075-site-vitrine`
- **PR** : —
- **Statut** : terminé le 2026-09-30 (PR créée)

## Contexte

Le 30 septembre 2026, le propriétaire a acheté **astreinte-sp.fr** et **astreint-sp.fr** chez OVH
pour la présentation du produit. Aujourd'hui, rien ne présente Astreinte SP à un chef de centre qui
ne le connaît pas : la seule adresse est l'app elle-même (`https://astreinte.staticflow.ch`).

## Décisions (propriétaire, 30 septembre 2026)

- Domaine principal **astreinte-sp.fr** (et `www.` qui y redirige) ; **astreint-sp.fr** redirige
  en 301 vers lui.
- Contact affiché : `jonathan.lemaine78@gmail.com`. Recommandation, à trancher au moment du brief :
  une redirection OVH `contact@astreinte-sp.fr` → cette adresse, pour ne pas exposer une adresse
  personnelle aux robots ; en attendant, l'adresse n'est pas écrite en clair dans le HTML (lien
  construit au clic).
- Pas de témoignage client tant que le propriétaire n'en a pas fourni un, signé et autorisé.
- L'app reste sur `astreinte.staticflow.ch` : la déplacer sur `app.astreinte-sp.fr` est un autre
  ticket (Supabase, Stripe, Firebase, iOS, liens des courriels).

## À faire

1. **Brief de design** (`ui-designer`, Impeccable en mode **Persuade**, `PRODUCT.md`) :
   `design/075-site-vitrine.md`. Public : chef de centre et bureau d'amicale de sapeurs-pompiers
   volontaires, souvent sur téléphone. Le site reprend l'identité de l'app (`DESIGN.md`) sans en
   copier les écrans d'outil.
2. **Site statique** dans `site/` (HTML et CSS, ou Astro si le brief le justifie ; pas Flutter) :
   - accroche et problème (planning d'astreinte sur papier, tableur, WhatsApp) ;
   - comment ça marche, en trois étapes (le pompier saisit ses dispos, l'admin construit le
     planning, chacun accepte et reçoit ses rappels) ;
   - captures réelles de l'app (PWA et iPhone), sans donnée personnelle réelle ;
   - prix : 55 €/mois ou 550 €/an, essai gratuit, « plus de 60 membres : nous contacter » ;
   - FAQ : données et RGPD, hébergement en Europe, iPhone et Android, hors ligne, résiliation ;
   - boutons « Essayer gratuitement » vers l'app et contact ;
   - **mentions légales** (éditeur Staticflow LLC, directeur de publication, hébergeur Vercel),
     **politique de confidentialité** du site ; aucune trace sans consentement (statistiques sans
     cookies seulement, Vercel Web Analytics ou rien) ;
   - SEO : titre, description, Open Graph, `sitemap.xml`, `robots.txt`, données structurées
     `SoftwareApplication`, `lang="fr"`, favicon et image de partage ;
   - accessibilité : contrastes AA, navigation au clavier, textes alternatifs, pas d'emoji comme
     icônes.
3. **Hébergement** : projet Vercel séparé de la PWA, déployé par l'API comme la PWA
   (voir la mémoire de déploiement et `deploy.yml`) ; le workflow ne déploie le site que quand
   `site/` change.
4. **DNS chez OVH** : enregistrements à ajouter (A/CNAME Vercel pour les deux domaines et `www`),
   donnés au propriétaire, ou posés par l'API OVH si une clé est fournie (rangée dans 1Password,
   coffre Static Flow). HTTPS actif sur les quatre noms.
5. **Docs** : `docs/DEPLOIEMENT.md` (site vitrine) et une ligne dans `CLAUDE.md` (sources de
   vérité).

## Décisions (propriétaire, 30 septembre 2026, points ouverts du brief)

1. Pas d'inscription en libre-service : le bouton principal devient « Demander un essai gratuit »
   (courriel prérempli vers `contact@astreinte-sp.fr`), « Se connecter » mène à l'app.
2. Vouvoiement collectif ; le nom public est « Astreinte SP ».
3. Résiliation effective à la fin de la période payée.
4. Base Supabase en France (`eu-west-3`, Paris) ; les push passent par Firebase (Google,
   États-Unis), et le site le dit.
5. Prix : 55 €/mois, 550 €/an (valeurs Stripe de production).
6. Restent à compléter par le propriétaire, marqués `[À COMPLÉTER …]` : mention TVA, adresse, État
   et numéro d'enregistrement de Staticflow LLC, directeur de la publication (Jonathan Lemaine, à
   confirmer), et les rubriques de confidentialité du brief § 8.2.
7. Captures depuis `supabase db reset` et un planning fictif, en AVIF et WebP avec budgets.
8. Projet Vercel séparé, déployé par l'API ; le projet et le DNS sont créés par le propriétaire
   (`docs/DEPLOIEMENT.md` § 11).

## Critères d'acceptation

- `https://astreinte-sp.fr` sert le site en HTTPS ; `www.astreinte-sp.fr`, `astreint-sp.fr` et
  `www.astreint-sp.fr` redirigent en 301 vers lui.
- Lighthouse mobile ≥ 95 en performance, accessibilité, bonnes pratiques et SEO (rapport joint).
- Aucun cookie ni requête vers un tiers de suivi au chargement.
- Mentions légales et confidentialité présentes et liées depuis chaque page.
- Le bouton principal « Demander un essai gratuit » ouvre un courriel prérempli vers
  `contact@astreinte-sp.fr`, adresse jamais écrite en clair dans le HTML ; le lien « Se connecter »
  ouvre l'app (`https://astreinte.staticflow.ch`). Le prix affiché (55 €/mois, 550 €/an) égale
  celui de l'écran Abonnement en production (`STRIPE_AMOUNT_MONTHLY=5500`,
  `STRIPE_AMOUNT_YEARLY=55000`).
- Rendu vérifié à 390 et 1280 px, clair et sombre si le brief le prévoit.
- La CI vérifie le site (liens internes, HTML valide, poids des images) et reste verte ; toutes les
  commandes des jobs rejouées en local avant le push. Les marques `[À COMPLÉTER` sont listées par
  la CI des PR sans la faire échouer ; elles bloquent seulement la mise en ligne du site
  (`deploy.yml`).

## Hors périmètre

- Déplacer l'app sur `app.astreinte-sp.fr`.
- Blog, pages multiples par département, formulaire de contact avec serveur.
