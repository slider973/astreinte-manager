-- 0027 — Export RGPD : tout ce que la base sait d'une personne, et rien d'autre.
-- Référence : docs/PRD.md § 8 (RGPD), docs/SCHEMA.md § 2 (table par table) et § 7,
-- docs/RGPD.md, design/034-rgpd-export.md. Ticket 034.
--
-- Pourquoi une fonction SQL, et pas douze requêtes depuis l'Edge Function
-- ----------------------------------------------------------------------
-- Trois raisons, dans cet ordre :
--
--   1. **Un seul instantané.** Douze appels PostgREST successifs peuvent tomber de
--      part et d'autre d'une écriture : un export où une disponibilité apparaît
--      dans le journal d'audit mais pas dans la liste des disponibilités est un
--      export faux. Ici tout est lu dans la même requête, donc dans le même
--      instantané.
--   2. **Une seule définition de « ce qui concerne cette personne ».** Elle est
--      écrite ici, à côté du schéma, et `supabase/tests/export_rgpd_test.sql` la
--      vérifie table par table à chaque PR — y compris en CI, où les Edge
--      Functions ne sont pas joignables.
--   3. **Le même verrou que `delete_own_account` (0026).** Le paramètre
--      `p_user_id` est ce qui ferme la fonction aux clients : `revoke` nommé sur
--      `anon` et `authenticated`, `grant` au seul `service_role`, et l'Edge
--      Function tire l'identité du JWT. Sans ce verrou, `p_user_id` serait une
--      porte pour lire le dossier complet de n'importe qui.
--
-- Les trois frontières, et elles sont un choix de produit
-- ------------------------------------------------------
--   - **Ce qui part avec la personne** : son profil, ses appartenances, ses
--     disponibilités, ses préférences de charge, ses attributions, ses
--     notifications, ses appareils, les invitations qu'elle a reçues, celles
--     qu'elle a envoyées, et les actes d'administration qui portent sur elle.
--   - **Ce qui est recopié pour rendre le fichier lisible seul** : le nom de la
--     caserne, la date et le créneau d'une attribution, l'année et le mois d'une
--     préférence, le statut du planning. Ce sont des colonnes de `stations`,
--     `shifts`, `periods` et `schedules` — des données de caserne — mais sans
--     elles l'export est une liste d'UUID, donc illisible, donc inutile.
--   - **Ce qui n'y entre jamais** : le nom, le prénom, l'adresse ou l'identifiant
--     d'une autre personne. Un export RGPD qui livre le dossier d'un tiers est
--     lui-même une violation. D'où : l'administrateur qui a saisi une
--     disponibilité à ma place est un **booléen**, pas un nom ; l'attribution qui
--     a remplacé la mienne est un **booléen**, pas un identifiant ; l'adresse que
--     j'ai invitée est **masquée** (`mask_email`, 0009) ; le `data` d'une ligne
--     d'audit est filtré par liste blanche.
--
-- Tables du § 2 volontairement absentes, et pourquoi :
--   - `periods`, `shifts`, `schedules`, `stations.settings` : configuration et
--     calendrier de la caserne, identiques pour tous ses membres. Ce ne sont pas
--     mes données ; ce qu'elles ont d'utile est recopié ci-dessus.
--   - `subscriptions`, `stripe_events` : l'abonnement lie la caserne au
--     prestataire de paiement. Aucune colonne ne désigne un membre.
--   - `notification_outbox` : file d'attente technique, multi-casernes, jamais
--     lue par un client (§ 2.16). Ce qui m'y concernait a produit une ligne
--     `notifications`, qui est dans l'export.
--   - `invitations.token` : porteur de droits, hors du `grant` de `select` du
--     rôle `authenticated` depuis `0008`. Un jeton recopié dans un fichier qui
--     voyage par courriel est un jeton compromis.
--   - `super_admins` : présente, mais réduite à un booléen — la table n'a pas
--     d'autre colonne que la clé et une date.

-- ===========================================================================
-- export_own_data — le dossier complet d'une personne, en un seul instantané
-- ===========================================================================
-- Retour : `{"ok": true, "donnees": {…}, "inventaire": {section: n, …}}`, ou
-- `{"ok": false, "code": "profile_missing"}`. Jamais d'exception pour un refus
-- métier : l'Edge Function doit pouvoir traduire le code en phrase française.
--
-- `inventaire` n'est pas décoratif : c'est lui qui permet de vérifier, sans
-- relire tout le fichier, que chaque section attendue est présente — y compris
-- vide. Une section absente et une section vide ne disent pas la même chose.
create function export_own_data(p_user_id uuid) returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_email        text;
  v_profil       jsonb;
  v_casernes     jsonb;
  v_appartenances jsonb;
  v_dispos       jsonb;
  v_preferences  jsonb;
  v_attributions jsonb;
  v_notifs       jsonb;
  v_appareils    jsonb;
  v_inv_recues   jsonb;
  v_inv_envoyees jsonb;
  v_actes_sur_moi jsonb;
  v_mes_actes    jsonb;
  v_editeur      boolean;
begin
  select p.email,
         jsonb_build_object(
           'id',                          p.id,
           'prenom',                      p.first_name,
           'nom',                         p.last_name,
           'email',                       p.email,
           'telephone',                   p.phone,
           'notifications_non_critiques', p.push_enabled,
           'langue',                      p.locale,
           'cree_le',                     p.created_at,
           'modifie_le',                  p.updated_at)
    into v_email, v_profil
  from profiles p
  where p.id = p_user_id;

  if v_profil is null then
    return jsonb_build_object('ok', false, 'code', 'profile_missing');
  end if;

  -- ------------------------------------------------------------------
  -- Les casernes où cette personne est — ou a été — membre
  -- ------------------------------------------------------------------
  -- Ni `settings` ni l'abonnement : ce sont les réglages du centre, pas les
  -- données du pompier. Le nom, l'identifiant et le fuseau suffisent à rendre
  -- le reste du fichier lisible.
  select coalesce(jsonb_agg(ligne order by tri), '[]'::jsonb) into v_casernes
  from (
    select distinct s.name as tri,
           jsonb_build_object(
             'id',          s.id,
             'nom',         s.name,
             'identifiant', s.slug,
             'fuseau',      s.timezone) as ligne
    from memberships m
    join stations s on s.id = m.station_id
    where m.user_id = p_user_id
  ) casernes;

  select coalesce(jsonb_agg(ligne order by tri), '[]'::jsonb)
    into v_appartenances
  from (
    select m.joined_at as tri, jsonb_build_object(
             'id',            m.id,
             'caserne_id',    m.station_id,
             'caserne',       s.name,
             'role',          m.role,
             'statut',        m.status,
             'nom_affiche',   m.display_name,
             'competences',   to_jsonb(m.skills),
             'rejointe_le',   m.joined_at,
             'desactivee_le', m.disabled_at,
             'creee_le',      m.created_at,
             'modifiee_le',   m.updated_at) as ligne
    from memberships m
    join stations s on s.id = m.station_id
    where m.user_id = p_user_id
  ) appartenances;

  -- ------------------------------------------------------------------
  -- Disponibilités
  -- ------------------------------------------------------------------
  -- `set_by` désigne **quelqu'un d'autre** quand un administrateur a saisi à ma
  -- place. Le fait me concerne — il explique une case que je n'ai pas cochée —
  -- mais l'identité de l'administrateur ne m'appartient pas. D'où un booléen.
  select coalesce(jsonb_agg(ligne order by tri_date, tri_slot), '[]'::jsonb)
    into v_dispos
  from (
    select a.date as tri_date, a.slot as tri_slot, jsonb_build_object(
             'caserne',    s.name,
             'date',       a.date,
             'creneau',    a.slot,
             'statut',     a.status,
             'saisie_par_un_administrateur',
                           a.set_by is not null and a.set_by <> a.user_id,
             'creee_le',   a.created_at,
             'modifiee_le', a.updated_at) as ligne
    from availabilities a
    join stations s on s.id = a.station_id
    where a.user_id = p_user_id
  ) dispos;

  select coalesce(jsonb_agg(ligne order by tri_annee, tri_mois), '[]'::jsonb)
    into v_preferences
  from (
    select pe.year as tri_annee, pe.month as tri_mois, jsonb_build_object(
             'caserne',      s.name,
             'annee',        pe.year,
             'mois',         pe.month,
             'max_gardes',   ap.max_shifts,
             'max_weekends', ap.max_weekends,
             'commentaire',  ap.comment,
             'creee_le',     ap.created_at,
             'modifiee_le',  ap.updated_at) as ligne
    from availability_preferences ap
    join periods  pe on pe.id = ap.period_id
    join stations s  on s.id = ap.station_id
    where ap.user_id = p_user_id
  ) preferences;

  -- ------------------------------------------------------------------
  -- Attributions — ce qui reste après une suppression de compte (0026)
  -- ------------------------------------------------------------------
  -- `created_by` et `replaced_by` désignent des tiers : le premier est
  -- l'administrateur qui a monté le planning, le second une attribution qui
  -- appartient, le plus souvent, à quelqu'un d'autre. Les deux deviennent des
  -- booléens — le fait reste, la personne disparaît.
  select coalesce(jsonb_agg(ligne order by tri_date, tri_slot), '[]'::jsonb)
    into v_attributions
  from (
    select sh.date as tri_date, sh.slot as tri_slot, jsonb_build_object(
             'id',                 asg.id,
             'caserne',            s.name,
             'date',               sh.date,
             'creneau',            sh.slot,
             'statut',             asg.status,
             'j_etais_disponible', asg.was_available,
             'proposee_le',        asg.proposed_at,
             'repondu_le',         asg.responded_at,
             'motif',              asg.decline_reason,
             'remplacee',          asg.replaced_by is not null,
             'rappels_envoyes',    asg.reminder_count,
             'dernier_rappel_le',  asg.last_reminder_at,
             'planning',           sch.status,
             'creee_le',           asg.created_at) as ligne
    from assignments asg
    join shifts    sh  on sh.id  = asg.shift_id
    join schedules sch on sch.id = sh.schedule_id
    join stations  s   on s.id   = asg.station_id
    where asg.user_id = p_user_id
  ) attributions;

  -- ------------------------------------------------------------------
  -- Notifications reçues, et appareils qui les reçoivent
  -- ------------------------------------------------------------------
  -- `data` est le lien profond de la notification (§ 2.12) : il ne désigne que
  -- mes propres attributions, il reste tel quel.
  select coalesce(jsonb_agg(ligne order by tri), '[]'::jsonb)
    into v_notifs
  from (
    select n.created_at as tri, jsonb_build_object(
             'id',          n.id,
             'caserne',     s.name,
             'type',        n.type,
             'canal',       n.channel,
             'titre',       n.title,
             'texte',       n.body,
             'lien',        n.data,
             'envoyee_le',  n.sent_at,
             'delivree',    n.delivered,
             'lue_le',      n.read_at,
             'erreur',      n.error,
             'creee_le',    n.created_at) as ligne
    from notifications n
    left join stations s on s.id = n.station_id
    where n.user_id = p_user_id
  ) notifs;

  -- Le jeton d'un appareil n'est pas une donnée fournie par la personne : c'est
  -- un identifiant d'installation émis par Firebase, sans valeur pour elle et
  -- réutilisable par qui le lit. On en garde les douze derniers caractères, ce
  -- qui suffit à reconnaître un appareil dans la liste sans faire voyager un
  -- identifiant utilisable dans un fichier rangé dans un dossier « Téléchargements ».
  select coalesce(jsonb_agg(ligne order by tri), '[]'::jsonb)
    into v_appareils
  from (
    select t.last_seen_at as tri, jsonb_build_object(
             'appareil',    t.device_label,
             'plateforme',  t.platform,
             'jeton_fin',   right(t.token, 12),
             'vu_le',       t.last_seen_at,
             'cree_le',     t.created_at) as ligne
    from push_tokens t
    where t.user_id = p_user_id
  ) appareils;

  -- ------------------------------------------------------------------
  -- Invitations : celles que j'ai reçues, celles que j'ai envoyées
  -- ------------------------------------------------------------------
  -- Jamais `token`, dans un sens comme dans l'autre. Et l'adresse d'un invité
  -- est masquée : l'acte d'inviter m'appartient, l'adresse appartient à l'autre.
  select coalesce(jsonb_agg(ligne order by tri), '[]'::jsonb)
    into v_inv_recues
  from (
    select i.created_at as tri, jsonb_build_object(
             'caserne',     s.name,
             'role',        i.role,
             'expire_le',   i.expires_at,
             'acceptee_le', i.accepted_at,
             'creee_le',    i.created_at) as ligne
    from invitations i
    join stations s on s.id = i.station_id
    where lower(i.email) = lower(v_email)
  ) recues;

  select coalesce(jsonb_agg(ligne order by tri), '[]'::jsonb)
    into v_inv_envoyees
  from (
    select i.created_at as tri, jsonb_build_object(
             'caserne',         s.name,
             'adresse_masquee', mask_email(i.email),
             'role',            i.role,
             'acceptee',        i.accepted_at is not null,
             'creee_le',        i.created_at) as ligne
    from invitations i
    join stations s on s.id = i.station_id
    where i.invited_by = p_user_id
  ) envoyees;

  -- ------------------------------------------------------------------
  -- Journal d'audit — deux sections, deux points de vue
  -- ------------------------------------------------------------------
  -- 1. Ce qu'un administrateur a fait **sur mes données**. C'est la promesse de
  --    `docs/PRD.md § 7` règle 7 (« toute action d'admin sur les données d'un
  --    membre est tracée ») rendue lisible par l'intéressé. Les acteurs sont
  --    reconnus par les trois clés que les migrations 0012, 0018 et 0020
  --    utilisent pour désigner le membre concerné, plus `entity_id` quand
  --    l'entité est le profil lui-même (`account.deleted`, 0026).
  --
  --    `data` est filtré par **liste blanche** : `reason`, `previous_user`,
  --    `to_user` et les identifiants de tiers n'en sortent pas. Une liste noire
  --    laisserait passer la prochaine clé ajoutée par une migration.
  select coalesce(jsonb_agg(ligne order by tri), '[]'::jsonb)
    into v_actes_sur_moi
  from (
    select al.created_at as tri, jsonb_build_object(
             'le',      al.created_at,
             'caserne', s.name,
             'acte',    al.action,
             'objet',   al.entity,
             'details', coalesce(
                          (select jsonb_object_agg(cle, valeur)
                             from jsonb_each(al.data) as d(cle, valeur)
                            where cle in ('date', 'slot', 'status', 'statut_avant',
                                          'previous_status', 'was_available',
                                          'period', 'role')),
                          '{}'::jsonb)) as ligne
    from audit_log al
    left join stations s on s.id = al.station_id
    where al.data ->> 'user_id'       = p_user_id::text
       or al.data ->> 'to_user'       = p_user_id::text
       or al.data ->> 'previous_user' = p_user_id::text
       or (al.entity = 'profile' and al.entity_id = p_user_id)
  ) actes;

  -- 2. Ce que j'ai fait moi-même, quand j'administre une caserne. L'acte
  --    m'appartient ; son `data` décrit presque toujours quelqu'un d'autre —
  --    l'adresse que j'ai invitée, le membre que j'ai attribué. Il n'est donc
  --    **pas** repris : l'acte, l'objet, la date et la caserne, rien de plus.
  select coalesce(jsonb_agg(ligne order by tri), '[]'::jsonb)
    into v_mes_actes
  from (
    select al.created_at as tri, jsonb_build_object(
             'le',      al.created_at,
             'caserne', s.name,
             'acte',    al.action,
             'objet',   al.entity) as ligne
    from audit_log al
    left join stations s on s.id = al.station_id
    where al.actor_id = p_user_id
  ) miens;

  select exists (select 1 from super_admins sa where sa.user_id = p_user_id)
    into v_editeur;

  return jsonb_build_object(
    'ok', true,
    'donnees', jsonb_build_object(
      'profil',                          v_profil,
      'casernes',                        v_casernes,
      'appartenances',                   v_appartenances,
      'disponibilites',                  v_dispos,
      'preferences_de_charge',           v_preferences,
      'attributions',                    v_attributions,
      'notifications',                   v_notifs,
      'appareils',                       v_appareils,
      'invitations_recues',              v_inv_recues,
      'invitations_envoyees',            v_inv_envoyees,
      'actes_administratifs_me_concernant', v_actes_sur_moi,
      'mes_actes_administratifs',        v_mes_actes,
      'editeur_du_produit',              v_editeur),
    'inventaire', jsonb_build_object(
      'profil',                          1,
      'casernes',                        jsonb_array_length(v_casernes),
      'appartenances',                   jsonb_array_length(v_appartenances),
      'disponibilites',                  jsonb_array_length(v_dispos),
      'preferences_de_charge',           jsonb_array_length(v_preferences),
      'attributions',                    jsonb_array_length(v_attributions),
      'notifications',                   jsonb_array_length(v_notifs),
      'appareils',                       jsonb_array_length(v_appareils),
      'invitations_recues',              jsonb_array_length(v_inv_recues),
      'invitations_envoyees',            jsonb_array_length(v_inv_envoyees),
      'actes_administratifs_me_concernant', jsonb_array_length(v_actes_sur_moi),
      'mes_actes_administratifs',        jsonb_array_length(v_mes_actes)));
end $$;

comment on function export_own_data(uuid) is
  'Export RGPD (ticket 034) : profil, casernes, appartenances, disponibilités, préférences de charge, attributions, notifications, appareils, invitations reçues et envoyées, actes d''audit concernant la personne et actes qu''elle a elle-même posés. Aucune donnée nominative d''un tiers : les autres personnes apparaissent en booléen ou en adresse masquée. Réservée au rôle de service : l''identité vient du JWT, pas du paramètre.';

-- Même verrou que `delete_own_account` (0026) et que les fonctions d'invitation
-- (0009) : une fonction qui prend un `user_id` en paramètre n'a rien à faire
-- dans l'API cliente. `revoke from public` ne suffit pas — `api.auto_expose_new_tables`
-- pose des grants nominatifs sur `anon` et `authenticated`.
revoke all on function export_own_data(uuid) from public, anon, authenticated;
grant execute on function export_own_data(uuid) to service_role;
