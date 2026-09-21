# 040 — Rendre visible une notification définitivement perdue

- **Épopée** : E6 Notifications
- **Priorité** : P0
- **Dépend de** : 025, 026
- **Branche** : `feat/040-ligne-interne-echec-definitif`
- **Statut** : terminé le 2026-09-21 (PR créée)

## Contexte
Relevé en revue du ticket 025, puis tranché au ticket 026. Une demande d'envoi qui échoue cinq fois
passe en abandon et ne laisse aucune ligne visible par le membre : seule une requête d'exploitation
la révèle. Un pompier à qui on a proposé une astreinte peut donc ne jamais l'apprendre, et personne
ne s'en aperçoit. C'est précisément ce que la file d'attente devait rendre impossible.

Décision prise au ticket 026 : écrire la ligne interne au moment de l'abandon, plutôt qu'alerter
les administrateurs. Le destinataire est celui qui perd quelque chose, et prévenir un chef de centre
transformerait un incident technique en tâche humaine chez des bénévoles un samedi soir. Le centre
de notifications est déjà le filet du membre sans notification poussée.

L'écran est prêt : il lit déjà la colonne d'erreur et affiche « L'envoi a échoué, tu ne l'as
peut-être pas reçue ».

## À faire
- À l'abandon d'une demande, écrire la ligne interne du destinataire avec sa mention d'échec.
- Décider comment produire les libellés français : la tâche planifiée est en SQL, alors que les
  textes sont construits dans le code des fonctions serveur. Soit appeler la fonction d'envoi dans
  un mode qui n'écrit que la ligne interne, soit déplacer la construction des textes en base. Ne pas
  dupliquer les phrases dans deux langages.
- Tester le chemin complet : cinq échecs, abandon, ligne visible par le membre avec sa mention.

## Critères d'acceptation
- Une demande abandonnée après cinq tentatives laisse une ligne lisible par son destinataire.
- Aucune phrase française n'est écrite à deux endroits.
