# `polices-de-repli/` — un répertoire vide, exprès

Quand un texte contient un glyphe qu'aucune police chargée ne sait dessiner — un emoji tapé dans
un commentaire, un nom en cyrillique ou en arabe —, le moteur Flutter web cherche la police
**Noto** qui le couvre et la télécharge. Par défaut, il la prend sur `https://fonts.gstatic.com/s/`.

Ce n'est pas une requête de démarrage : elle part **pendant la navigation**, déclenchée par le
texte saisi par les utilisateurs. C'est donc la pire des deux — invisible en recette, et sortante
au moment précis où l'application manipule des données personnelles.

`web/flutter_bootstrap.js` pointe donc `fontFallbackBaseUrl` sur `polices-de-repli/`, c'est-à-dire
**ici**. Aucune police n'y est déposée : le catalogue Noto complet pèse plusieurs centaines de
mégaoctets et le produit est en français. La requête échoue donc chez nous, le moteur écrit
`Failed to parse fallback font …` en console et dessine un caractère de substitution.

C'est le comportement voulu :

- un carré à la place d'un emoji dans un commentaire est un défaut d'affichage mineur ;
- une requête vers un serveur américain à chaque fois qu'on affiche ce commentaire est un écart
  au registre des données personnelles (`docs/PRD.md` § 8).

Le jeu de caractères réellement couvert par les polices embarquées (latin, diacritiques français,
guillemets, `€`, flèches…) est décrit dans `assets/fonts/README.md`. Si un besoin d'alphabet
supplémentaire apparaît un jour, la réponse est d'élargir ce sous-ensemble — pas de rouvrir la
porte de `fonts.gstatic.com`.

Ce fichier existe aussi pour que le répertoire survive à Git, qui ne versionne pas les répertoires
vides.
