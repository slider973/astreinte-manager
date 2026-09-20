# 026 — Centre de notifications — brief de design

Mode Impeccable : **Operate**. Monde visuel : le registre de garde (`DESIGN.md`).
Périmètre : la PWA. Bref, parce que l'écran est un registre de plus.

## 0. Ce que cet écran est

Le journal de bord d'un pompier : **une ligne par événement, la plus récente en haut, rien
qu'on efface.** Ce n'est pas une boîte de réception qu'on trie, ce n'est pas un fil
d'actualité. On l'ouvre pour deux raisons, et deux seulement :

1. « j'ai vu passer quelque chose et je n'ai pas eu le temps de le lire » ;
2. « mon téléphone n'a rien affiché — qu'est-ce que j'ai raté ? »

Le second cas est le plus important : c'est **le seul filet** de ce produit quand le push
n'arrive pas (iPhone hors écran d'accueil, autorisation refusée, batterie économisée). Une
proposition d'astreinte jamais lue est une garde non couverte. Le centre existe pour ça.

Conséquence de composition : pas de carte, pas d'ombre, pas d'avatar, pas de regroupement par
jour. Des lignes réglées séparées par un filet de 1 dp, comme la liste des membres.

## 1. La ligne

```
┌────────────────────────────────────────────────┐
│ ■  📥 Une astreinte t'est proposée   il y a 2 h │   ← non lue
│    Samedi 4 octobre, nuit. Réponds avant…      │
├────────────────────────────────────────────────┤
│    ✅ Planning validé                 hier     │   ← lue
│    Ton mois d'octobre est validé.              │
└────────────────────────────────────────────────┘
```

De gauche à droite : la **marque de non-lue**, l'**icône du type**, le **titre**, la **date
relative** en marge droite, puis le corps sur deux lignes au plus.

**La non-lue porte quatre signaux, la couleur en dernier** (`DESIGN.md § Overview`) :

| Signal | Non lue | Lue |
|---|---|---|
| Marque | carré plein 10 dp, rayon `case` (4) | rien, l'espace reste réservé |
| Graisse du titre | 600 | 400 |
| Fond de ligne | `surface-container-low` | `surface` |
| Semantics | « Non lue. » en tête du libellé | rien |
| Couleur de la marque | `etat-info` | — |

La marque est **le carré du registre**, pas une pastille : le rayon `pastille` est réservé aux
compteurs (`DESIGN.md § Rayons`). Photocopiée en noir et blanc, la ligne non lue reste
reconnaissable — c'est le test de la direction.

**Une icône par type**, Material, un seul style contour, jamais un emoji :

| Type | Icône |
|---|---|
| `assignment_proposed` | `inbox` |
| `assignment_reminder`, `availability_reminder` | `schedule` |
| `assignment_changed` | `edit_calendar` |
| `assignment_cancelled`, `assignment_declined` | `event_busy` |
| `schedule_validated`, `schedule_all_accepted` | `event_available` |
| `late_responders` | `group` |
| type inconnu | `notifications` |

Un type inconnu **ne casse rien** : le backend peut en ajouter un avant que l'app soit
redéployée, et une notification qu'on ne sait pas classer reste une notification qu'on doit
lire.

**La date est relative en deçà d'une semaine** (« il y a 20 min », « hier »), absolue ensuite
(« 15 sept. »). Entre deux activités, on ne compte pas des jours.

**Cible tactile** : la ligne entière est touchable, hauteur ≥ 64 dp, jamais un bouton
« Ouvrir » à côté du texte.

## 2. Le geste

Une touche fait **deux choses dans le même mouvement** : la ligne passe lue, et la destination
s'ouvre. Pas de confirmation, pas de bouton séparé « marquer lu » par ligne — un pompier avec
des gants ne vise pas une seconde cible.

La destination passe par `destinationInterne` (ticket 024), **la même fonction, pas une
seconde**. Un lien inconnu ou refusé (un `/admin/schedule/…` chez un membre rétrogradé) ramène
à l'accueil **sans message d'erreur** : le membre n'a rien fait de mal. Et la ligne est quand
même marquée lue — il l'a bien lue.

Le marquage est **optimiste** : la ligne change tout de suite, l'écriture part derrière. Si la
base refuse, la ligne redevient non lue et une bannière d'erreur le dit. Le contraire — une
ligne qui attend le réseau pour changer d'aspect — donne une application cassée en 4G de
caserne.

## 3. Tout marquer comme lu

Un bouton **nommé**, secondaire, pleine largeur, en bas de l'écran (`filActions`) : c'est là
que le pouce arrive, et 52 dp de haut. Pas une icône `done_all` dans la barre — le public de ce
produit ne lit pas les icônes seules (`DESIGN.md § Don't`).

Il **n'apparaît que s'il y a des non-lues.** Un bouton désactivé qu'il faudrait expliquer à
côté vaut moins qu'un bouton absent : quand tout est lu, il n'y a rien à faire.

## 4. La pastille

**Elle ne va pas dans la barre de navigation** : `DESIGN.md § Navigation` fixe cinq
destinations au maximum, et un admin en a déjà cinq. Aucune ne s'ajoute sans en retirer une, et
aucune ne mérite d'être retirée pour un journal.

La pastille va donc sur une **cloche dans la barre d'application de la coquille d'accueil**,
présente sur les quatre onglets. `Badge.count`, plafond « 9+ », doublée d'un libellé annoncé
(« 3 notifications non lues »), exactement comme la pastille « Propositions ». Sans non-lue :
pas de pastille, la cloche reste.

## 5. Les états

| État | Ce qu'on montre |
|---|---|
| Chargement | squelette à la forme de la liste : cinq lignes. Jamais de roue. |
| Vide | « Rien pour l'instant. » + « Les propositions d'astreinte et les infos de ta caserne arriveront ici. » Icône `notifications_none`. Pas d'action : il n'y a rien à faire, et le dire est honnête. |
| Erreur, liste vide | `EmptyState.erreur` + « Réessayer ». |
| Erreur, liste déjà à l'écran | bannière `erreur` + « Réessayer ». On ne vide jamais un écran juste parce qu'une relecture a échoué. |

## 6. Rester à jour sans relancer l'application

**Le temps réel n'est pas disponible.** Vérifié sur la base locale : `pg_publication_tables`
est vide, `notifications` n'est dans aucune publication, et aucune migration ne l'y met.
`docs/SCHEMA.md § 9` le dit noir sur blanc — « Aucune table n'est encore dans la publication
`supabase_realtime` (elle sera posée avec les plannings, ticket 017) ». S'abonner ici
produirait un canal silencieux qui ne lèverait jamais : la pire des pannes, celle qui a l'air
de marcher.

À la place, **trois déclencheurs de relecture**, tous dans `CoucheNotifications` — donc actifs
quel que soit l'écran affiché, et la pastille se met à jour avec :

1. **un push reçu au premier plan** — le message *est* le signal, et il porte déjà la ligne ;
2. **une notification touchée depuis l'arrière-plan** (service worker) ;
3. **le retour de l'application au premier plan**, comme au ticket 009.

Le critère d'acceptation « une notification push reçue apparaît aussi dans la liste sans
relancer l'app » est donc tenu par le chemin 1, sans Realtime. Ce qui n'est pas tenu : une
notification arrivée alors que l'onglet est fermé et le push muet (iPhone non installé)
n'apparaît qu'au retour au premier plan. C'est le minimum acceptable annoncé, et il faut
rouvrir l'abonnement quand le ticket 017 posera la publication.

## 7. La question laissée ouverte (remontée par la revue du ticket 025)

Une demande d'envoi qui finit `failed` dans `notification_outbox` ne laisse **aucune ligne
visible par le membre** : c'est l'Edge Function qui écrit la ligne `notifications`, et elle
n'a jamais tourné.

**Tranché : la ligne interne doit être écrite au moment de l'abandon, par
`cron_dispatch_notifications`.** Pas un bandeau pour l'admin. Trois raisons :

1. **Le destinataire est celui qui perd quelque chose.** Un bandeau chez l'admin transforme un
   incident technique en tâche humaine — « préviens Marie qu'elle a une astreinte » — sur un
   public de bénévoles. Ça ne tient pas un samedi soir.
2. **La ligne interne est déjà le filet du produit.** Le membre sans push vit avec : le centre
   est sa source. Une notification perdue doit y apparaître comme les autres, avec son titre,
   son corps et sa destination, marquée « L'envoi a échoué, tu ne l'as peut-être pas reçue. »
   La destination fonctionne, elle : le lien est calculable depuis la charge utile de l'outbox.
3. **C'est la promesse écrite du schéma** (`docs/SCHEMA.md § 2.11`) : « Livraison au moins une
   fois, jamais zéro ». Cinq échecs suivis de zéro trace contredisent la phrase.

**Non implémenté ici, et c'est délibéré.** L'écriture vit dans `cron_dispatch_notifications`
(migration SQL) : `CLAUDE.md` réserve les migrations à `supabase-dev`, et le contenu français
d'une notification est construit par `_shared/notification_content.ts`, pas par du SQL — la
tâche devra soit dupliquer les phrases, soit appeler l'Edge Function en mode « interne
seulement ». Ce n'est pas une ligne de code, c'est une décision d'architecture qui mérite son
ticket. **À ouvrir : « ligne interne d'échec définitif », dépend de 025, à faire avant la
première caserne réelle.**

Ce que le ticket 026 livre en attendant : la colonne `error` de `notifications` est lue par le
modèle, et une ligne qui la porte s'affiche avec sa mention d'échec. Le jour où le backend
écrit ces lignes, l'écran les montre déjà.
