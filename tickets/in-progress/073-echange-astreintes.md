# 073 — Échanger ou céder une astreinte entre pompiers

- **Épopée** : E4 Planning
- **Priorité** : P1
- **Dépend de** : 070, 071, 072
- **Branche** : `feat/073-echange-astreintes`
- **PR** : —
- **Statut** : en cours depuis 2026-10-04

## Contexte

Demande du propriétaire le 29 septembre 2026 : un pompier doit pouvoir échanger un jour ou une
nuit d'astreinte. Le PRD le range en v1.1 (§ 4.2 : « Échange d'astreinte entre deux membres avec
validation admin »). Rien n'existe : aujourd'hui, seul l'admin peut changer un titulaire, par
`reassign_shift`, après un refus ou de lui-même.

Ticket découpé en chantiers (une PR par chantier) : base, PWA, iOS.

## Décisions (recommandations acceptées par le propriétaire, 29 septembre 2026)

1. **Deux façons de demander.**
   - **À un collègue précis** : le pompier choisit un membre actif de sa caserne.
   - **À la caserne** (« je cherche un remplaçant ») : la demande est visible par tous les membres
     actifs **qui ont déclaré une disponibilité** sur ce créneau (jour ou nuit), et le premier qui
     accepte la prend. Les autres ne la voient pas : pas de bruit pour qui n'est pas libre.
2. **Deux formes.**
   - **Cession** : B prend la garde de A, sans contrepartie.
   - **Échange** : B prend la garde de A et A prend une garde de B, désignée dans la demande
     (seulement pour une demande à un collègue précis). Les deux mouvements passent ou échouent
     ensemble.
3. **Validation par l'admin, par défaut.** Après l'accord de B, la demande attend un admin. Un
   réglage de caserne (`station_settings`) permet la **validation automatique** quand le remplaçant
   avait déclaré une disponibilité `available` sur ce créneau ; l'admin est alors seulement
   informé. Réglage désactivé par défaut.
4. **Notifications (push, puis courriel de secours, comme le reste).** Demande reçue → B (ou les
   disponibles) ; accord de B → admins actifs ; validation ou refus → A et B ; demande expirée ou
   annulée → les intéressés. Rien n'est envoyé à qui n'est concerné.

## Règles métier

- Seule une attribution **`accepted`** d'un planning **publié ou validé**, sur un créneau
  **futur**, peut être proposée. Une seule demande ouverte par attribution.
- Le remplaçant doit être membre actif de la caserne, ne pas être déjà sur ce créneau, et ne pas
  dépasser ses plafonds `max_shifts` / `max_weekends` (même calcul que `v_member_load`). Avec le
  ticket 072 : pas pris sur un créneau qui chevauche dans une autre caserne.
- Une demande **expire** au début du créneau (et au plus tard à une échéance réglable, 24 h avant
  par défaut) ; une demande ouverte est annulable par A tant qu'elle n'est pas validée.
- **À la validation, en une transaction** (fonction `security definer`, verrous dans l'ordre de
  `reassign_shift`) : l'attribution de A passe `replaced` avec `replaced_by` vers une nouvelle
  attribution **`accepted`** de B (B a déjà dit oui), `audit_log`, notifications, réévaluation du
  planning. Pour un échange, même chose en miroir sur la garde de B. Si une condition ne tient plus
  (A n'est plus `accepted`, B a pris une autre garde, caserne suspendue, plafond atteint), rien ne
  change et la demande passe `failed` avec son motif.
- Caserne en lecture seule (suspension) : aucune demande ne se crée ni ne se valide.
- L'historique reste lisible : qui a demandé, qui a accepté, qui a validé, quand.

## À faire

1. **Base** (`supabase-dev`) : table `shift_exchanges` (statuts `open`, `accepted_by_peer`,
   `approved`, `rejected`, `cancelled`, `expired`, `failed` ; demandeur, attribution cédée,
   destinataire éventuel, attribution rendue pour un échange, repreneur, motif, horodatages), RLS
   (A et B voient la leur ; les disponibles voient les demandes « à la caserne » qui les
   concernent ; les admins voient celles de leur caserne), fonctions `request_exchange`,
   `respond_exchange`, `decide_exchange`, `cancel_exchange`, expiration par pg_cron, types de
   notification, réglage de validation automatique. **Mettre à jour `docs/SCHEMA.md` et
   `docs/WORKFLOWS.md`** (machine à états des échanges, séquence, liens profonds) dans la même PR,
   puisque la table n'y figure pas encore. Tests SQL de chaque règle, y compris les courses (deux
   repreneurs en même temps, validation pendant une réattribution admin).
2. **PWA** (`ui-designer` puis `flutter-dev`) : sur une astreinte à venir, « Proposer un échange »
   (collègue ou caserne, cession ou échange) ; dans la Boîte, demandes reçues et « à reprendre » ;
   côté admin, file des échanges à valider avec la charge de chacun ; états jamais portés par la
   couleur seule, cibles 44 pt. Écrans à jour (coordinateur du ticket 070).
3. **iOS** (fork `slider973/Foco`) : mêmes parcours pour le pompier (demander, répondre, suivre) ;
   l'admin valide depuis la PWA, seul canal de l'admin. Nouveau build TestFlight.
4. **PRD** : l'échange passe de v1.1 à livré ; décisions ci-dessus recopiées.

## Notes du chantier base (073a, migration `0041`)

- **Règle du 072 « pas pris ailleurs » : branchée** après la fusion de la PR #84.
  `exchange_rule_check` appelle `member_taken_elsewhere` (`0040`) : code `taken_elsewhere` à la
  demande et à l'accord, motif `peer_taken_elsewhere` / `requester_taken_elsewhere` à la
  validation ; une demande à la caserne ne parvient pas à qui est pris ailleurs. `exchange_apply`
  prend le verrou consultatif par pompier d'`apply_auto_proposal`, même clé, même ordre (uuid
  trié), après ses propres verrous : course vérifiée à deux sessions.
- Décisions du brief de design retenues en base : B ne revient pas sur son accord ; une demande à
  la caserne ne se décline pas ; B ne donne pas de motif ; l'admin n'annule pas la demande d'un
  pompier ; un plafond dépassé bloque ; échéance de 1 à 168 h, 24 par défaut ; une garde engagée
  dans une demande ouverte n'est pas proposable.

## Critères d'acceptation

- Tests SQL : cession et échange validés (statuts, `replaced_by`, attributions `accepted`, audit,
  notifications) ; chaque refus de règle ; expiration ; course de deux repreneurs (un seul gagne) ;
  un échange est tout ou rien ; aucune donnée d'une autre caserne lisible.
- Validation automatique : active seulement si le réglage l'est **et** si le remplaçant avait
  déclaré une disponibilité ; sinon, la demande attend l'admin.
- Tests widget PWA et tests de store iOS pour chaque parcours ; le parcours de bout en bout ajoute
  une cession validée par l'admin.
- `flutter analyze`, `flutter test`, `flutter build web` ; CI Deno ; CI iOS du fork verte ; build
  TestFlight publié.
- `docs/SCHEMA.md`, `docs/WORKFLOWS.md` et `docs/PRD.md` à jour.

## Hors périmètre

- Échange entre casernes différentes.
- Échange d'une garde contre plusieurs, ou chaîne d'échanges à trois.
- Bourse aux gardes ouverte hors des disponibles déclarés.
