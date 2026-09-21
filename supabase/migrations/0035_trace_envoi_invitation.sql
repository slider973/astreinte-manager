-- 0035 — La trace de l'envoi sur l'invitation. Ticket 048.
-- Référence : docs/SCHEMA.md sections 2.4 et 4.
--
-- Le problème que ça résout, constaté en production le 21 septembre 2026 : aucun
-- fournisseur de courriel n'était configuré, `sendMail` se repliait sur Mailpit à
-- une adresse interne à Docker qui n'existe pas en ligne, et rendait `sent: false`.
-- L'invitation était créée, le courriel ne partait jamais. `invite-member` le dit
-- bien dans sa réponse (`email_sent`), l'application le dit bien sur le moment —
-- puis l'information disparaît avec le compte rendu. Dans « Invitations en
-- attente », la ligne affiche ensuite « En attente » et sa date d'expiration,
-- exactement comme une invitation partie que le destinataire tarde à accepter.
-- L'administrateur attend une réponse que personne ne peut lui donner.
--
-- Pourquoi sur `invitations` et pas ailleurs : la trace existe déjà dans
-- `notifications` (`sent_at`, `error`), mais cette ligne est rattachée **au
-- destinataire**, et un administrateur n'a aucune raison de pouvoir lire les
-- notifications de quelqu'un d'autre — la politique de `notifications` dit
-- « soi-même » et doit continuer à le dire. La trace doit donc vivre sur
-- l'invitation, que l'administrateur lit déjà.
--
-- Deux colonnes, pas trois, et la forme est copiée sur `notifications` pour que ce
-- soit la même chose sous le même nom :
--
--   email_sent_at  — l'horodatage du dernier envoi **réussi** ;
--   email_error    — le motif du dernier échec, effacé par un succès.
--
-- Elles se lisent ensemble et disent quatre choses distinctes :
--
--   | email_sent_at | email_error | ce que ça veut dire                          |
--   |---------------|-------------|----------------------------------------------|
--   | null          | null        | **on ne sait pas** : rien n'a été tracé       |
--   | null          | posé        | personne n'a été prévenu, et voici pourquoi   |
--   | posé          | null        | le courriel est parti, à cette date           |
--   | posé          | posé        | un courriel est parti, le dernier renvoi non  |
--
-- « On ne sait pas » et « pas envoyé » ne sont pas la même chose : afficher le
-- second à la place du premier serait un nouveau mensonge, du même genre que celui
-- qu'on corrige ici. D'où la première ligne du tableau, et d'où le rattrapage du
-- § 3 : les invitations antérieures ne sont pas déclarées en échec d'office, elles
-- reçoivent ce que `notifications` sait déjà d'elles, et rien quand elle ne sait
-- rien.
--
-- Ce que la migration ne fait pas :
--
--   - pas de troisième colonne pour l'horodatage de l'échec : la ligne dit « le
--     courriel n'est pas parti », pas « il n'est pas parti à 14 h 03 » ; personne
--     n'a de geste à poser qui dépende de cette heure-là ;
--   - pas de fournisseur ni de compteur de tentatives : `notifications` et les
--     journaux de la fonction les portent déjà, pour qui diagnostique ;
--   - pas de retouche à `create_invitation`. La trace naît de ce que `sendMail`
--     rend, et `sendMail` est appelée **après** la transaction SQL. C'est
--     `invite-member` qui écrit, en création comme en renvoi, comme elle écrit
--     déjà `notifications` par `tracerNotification`.

-- ===========================================================================
-- 1. Les deux colonnes
-- ===========================================================================
alter table invitations
  add column email_sent_at timestamptz,
  add column email_error   text;

comment on column invitations.email_sent_at is
  'Horodatage du dernier envoi réussi du courriel d''invitation (ticket 048). Nul avec email_error nul : on ne sait pas. Écrite par l''Edge Function invite-member.';
comment on column invitations.email_error is
  'Motif du dernier échec d''envoi du courriel d''invitation (ticket 048), effacé par un envoi réussi. Posé avec email_sent_at nul : personne n''a jamais été prévenu.';

-- ===========================================================================
-- 2. Le grant de colonne
-- ===========================================================================
-- 0008 a retiré le `select` de table pour énumérer les colonnes, parce que `token`
-- est un porteur de droits. Une colonne ajoutée n'hérite pas de cette énumération :
-- sans ces deux lignes, l'écran « Membres » ne lirait pas la trace. Et c'est bien
-- l'énumération qu'on complète, pas le `grant` de table qu'on rétablit — `token`
-- reste dehors, et c'est toute la raison de cette forme.
--
-- La lecture reste gouvernée par `invitations_select_admin` (0007) : administrateur
-- actif de la caserne, et personne d'autre. La trace ne change rien à qui voit la
-- ligne, elle ajoute ce que cette ligne dit à qui la voyait déjà.
--
-- Côté écriture, rien ne bouge : la seule main qui écrit la trace est le rôle de
-- service, par `invite-member`. `invitations_update_admin` laisse par ailleurs un
-- administrateur modifier les lignes de sa propre caserne, ici comme avant cette
-- migration ; il pourrait donc s'écrire une fausse trace, mais il peut déjà
-- supprimer l'invitation entière, et il ne tromperait que lui-même.
grant select (email_sent_at, email_error) on invitations to authenticated;

-- ===========================================================================
-- 3. Les invitations antérieures — ce qu'on sait d'elles, et rien de plus
-- ===========================================================================
-- Elles sont nées avant les colonnes. Les laisser toutes à « on ne sait pas »
-- serait honnête mais inutilement pauvre : l'information existe, elle est dans
-- `notifications`, elle est seulement illisible pour l'administrateur. On la
-- recopie donc là où elle est désormais lisible.
--
-- L'appariement, volontairement étroit — une trace fausse serait pire que pas de
-- trace :
--   - même caserne, et même personne (l'adresse de l'invitation est celle du
--     profil destinataire de la notification) ;
--   - type `invitation` et canal `email` : les seules lignes qu'écrit
--     `tracerNotification` ;
--   - notification postérieure à la création de l'invitation, pour ne pas
--     attribuer à celle-ci l'envoi d'une invitation précédente, supprimée puis
--     recréée pour la même adresse ;
--   - la plus récente de ces lignes, parce qu'un renvoi en écrit une de plus et
--     que c'est le dernier envoi qui fait foi.
--
-- Seules les invitations **en attente** sont rattrapées : ce sont les seules que
-- l'écran affiche, et une invitation acceptée prouve à elle seule que quelqu'un a
-- été prévenu. Les lignes sans notification correspondante restent à nul des deux
-- côtés, c'est-à-dire à « on ne sait pas ».
--
-- Le compte part dans le journal de déploiement : sur une base vierge c'est zéro,
-- sur la production c'est le nombre d'invitations qui cessent d'être muettes.
do $$
declare v_rattrapees integer;
begin
  with derniere_trace as (
    select distinct on (i.id)
           i.id      as invitation_id,
           n.sent_at as sent_at,
           n.error   as error
      from invitations i
      join profiles p on lower(p.email) = lower(i.email)
      join notifications n
        on n.user_id    = p.id
       and n.station_id = i.station_id
       and n.type       = 'invitation'
       and n.channel    = 'email'
       and n.created_at >= i.created_at
     where i.accepted_at is null
     order by i.id, n.created_at desc
  )
  update invitations i
     set email_sent_at = t.sent_at,
         email_error   = left(t.error, 300)
    from derniere_trace t
   where t.invitation_id = i.id
     and (t.sent_at is not null or t.error is not null);

  get diagnostics v_rattrapees = row_count;
  raise notice '0035 : % invitation(s) en attente ont retrouvé leur trace d''envoi.',
    v_rattrapees;
end $$;
