# 061 — Un nouveau monde visuel, à partir de l'écran de l'admin

- **Épopée** : E0 Fondations
- **Priorité** : P1
- **Dépend de** : 004, 016, 017
- **Branche** : `feat/061-monde-visuel-admin`
- **PR** : https://github.com/slider973/astreinte-manager/pull/54 (chantier 061a), https://github.com/slider973/astreinte-manager/pull/55 (chantier 061b), https://github.com/slider973/astreinte-manager/pull/56 (chantier 061c-1), https://github.com/slider973/astreinte-manager/pull/57 (chantier 061c-2)
- **Statut** : terminé le 2026-09-23 (PR créée)

## Contexte

Demandé par le propriétaire le 22 septembre 2026, avec deux images de référence.

La première est un écran de planning d'équipe : navigation latérale sur grand écran, barre de
recherche et compte en tête, bandeau de trois chiffres du mois avec une barre de répartition, bande
de semaine avec le jour courant marqué, puis une ligne par personne, avatar et nom à gauche, ses
créneaux en blocs colorés avec heure, rôle et lieu. Elle est conservée hors dépôt le temps du brief
(`scratchpad/refs/061-reference-admin.png`).

La seconde est la charte de cette référence : police **Archivo** (Regular, Medium, SemiBold, Bold),
et cinq couleurs, violet `#B142E8`, indigo `#7655FA`, vert `#097C69`, orange `#F59638`, rose
`#F9357C`. Le propriétaire l'a envoyée sans commentaire : c'est une direction esthétique épinglée,
pas une suggestion.

Ce n'est donc pas une retouche de l'écran de la matrice, c'est un **monde visuel de remplacement**,
au sens d'Impeccable, qui commence par l'admin. `DESIGN.md` en vigueur date du ticket 004, bleu
nuit sur blanc, et `PRODUCT.md` fixe « une seule apparence partout ».

## Ce que le brief doit trancher, avec le propriétaire, avant tout code

1. **Le périmètre.** Appliquer le nouveau monde à tout le produit, écrans pompier compris, ou
   commencer par l'admin sur grand écran et étendre ensuite. Recommander, en tenant compte de
   « une seule apparence partout » et du coût de deux mondes qui coexistent.
2. **La palette et la lisibilité.** Sur fond blanc, `#B142E8`, `#F59638` et `#F9357C` sont sous
   le seuil de contraste pour du texte. Le contexte d'usage est binding : dehors, gants, lecture
   rapide. Décider où chaque couleur a le droit de vivre (blocs, accents, badges avec icône et
   texte) et où elle n'en a pas (texte, états seuls). Aucun état porté par la couleur seule.
3. **La typographie.** Archivo remplace-t-elle Atkinson Hyperlegible, choisie au 004 pour la
   lisibilité en extérieur ? Mesurer, pas supposer : chiffres tabulaires, largeur des noms dans
   la colonne figée, rendu à 360 points.
4. **La structure de l'écran de l'admin.** Navigation latérale sur grand écran à la place de la
   barre du bas ; bandeau de chiffres du mois (créneaux couverts, à pourvoir, réponses en attente)
   avec barre de répartition ; bande de semaine ; ligne par membre avec avatar et nom. **Garder le
   modèle jour / nuit** : la référence découpe en heures, nos créneaux sont deux par jour, la grille
   reste membres × jours × deux créneaux, ce que la matrice fait déjà. Ce qui change est la forme,
   pas le modèle.
5. **Ce qu'on ne copie pas.** Le logo et le nom de la référence, la boîte « premium », la barre de
   recherche si elle n'a pas d'objet chez nous, les cases horaires.

## À faire

- Brief `design/061-monde-visuel-admin.md` au format Impeccable, via `new-work` puis `shape`, avec
  les cinq décisions ci-dessus, chacune avec une recommandation et sa raison. Le brief est
  **présenté au propriétaire avant tout code**, et le ticket s'arrête là tant qu'il n'a pas tranché.
- Après validation : `DESIGN.md` réécrit par `document`, tokens, thème Flutter, puis les écrans
  dans l'ordre que le brief fixe. Ce découpage donnera probablement plusieurs tickets ; celui-ci
  porte le brief et, si le propriétaire le veut, le premier écran.

## Critères d'acceptation

- Le brief existe, répond aux cinq questions avec une recommandation chacune, et a été relu par le
  propriétaire.
- Toute couleur utilisée en texte respecte 4,5:1 sur son fond ; aucun état n'est porté par la
  couleur seule ; cibles tactiles 44 pt.
- Le modèle jour / nuit est conservé dans la grille de l'admin.
- Si un écran est livré dans ce ticket : `flutter analyze` sans avertissement, `flutter test`
  verts, `flutter build web` qui passe, détecteur Impeccable à vide, inspection à l'écran aux
  deux largeurs.

## Livraison

Le monde visuel de l'admin a été livré en quatre chantiers, un par PR :

- **061a** — tokens, thème Flutter et police Archivo, `DESIGN.md` réécrit par `document`.
- **061b** — la coquille de l'écran admin : navigation latérale sur grand écran, bandeau des
  chiffres du mois avec barre de répartition, bande de semaine.
- **061c-1** — les dates et la barre de commande de la matrice.
- **061c-2** — les cases d'attribution, les avatars à initiales et le panneau des candidats.

Le chantier **061d**, la passe de finition sur les écrans pompier, est repris par le ticket 064
(`tickets/backlog/064-monde-visuel-pompier.md`). Ce ticket-ci se ferme donc sur l'admin.

Les écarts entre le brief et le code livré sont consignés dans `DESIGN.md`, § « Écarts
d'implémentation (ticket 061b) » et § « Écarts d'implémentation (ticket 061c) ».
