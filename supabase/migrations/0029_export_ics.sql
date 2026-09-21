-- 0029 — Export calendrier : un flux ICS par membre, derrière un jeton à lui.
-- Référence : docs/PRD.md § 5.5 et § 6.6, docs/SCHEMA.md § 2.1, § 2.2, § 2.9,
-- § 2.10, § 4 et § 7, design/028-export-ics.md. Ticket 028.
--
-- Ce que cette migration pose
-- ---------------------------
--   1. `profiles.ics_token` : le secret d'abonnement, un par membre, régénérable.
--   2. Les **grants de colonne** qui le rendent illisible au reste de la caserne.
--   3. `my_ics_token()` et `rotate_ics_token()` : les deux seuls chemins d'un
--      client vers ce secret, et ils ne répondent que sur `auth.uid()`.
--   4. `ics_feed_events(text, date)` : ce que le flux a le droit de contenir,
--      défini une fois, en base, à côté de la RLS qu'il recopie.
--
-- L'adresse voyage, et tout part de là
-- ------------------------------------
-- Cette URL sera collée dans Google Agenda, donc lue par des serveurs qui ne
-- sont pas les nôtres, recopiée dans iCloud, peut-être envoyée par courriel à
-- soi-même. Elle se comporte comme un mot de passe qu'on affiche. Trois règles
-- en découlent, et elles sont toutes ici plutôt que dans l'Edge Function :
--
--   - **Elle ne donne que les astreintes acceptées de son porteur.** Pas ses
--     disponibilités, pas son profil, pas le nom d'un équipier, rien d'une autre
--     caserne. `ics_feed_events` ne joint jamais un second `assignments` ni un
--     second `profiles` : il n'y a pas de chemin vers quelqu'un d'autre.
--   - **Elle se révoque.** `rotate_ics_token()` remplace la valeur ; l'ancienne
--     adresse ne désigne plus personne à la transaction suivante. Pas de liste
--     de révocation, pas de délai de grâce — le secret *est* la clé de recherche.
--   - **Elle suit l'état du membre.** Une appartenance `disabled` — départ de la
--     caserne, compte supprimé (`0026`) — retire les astreintes de cette caserne
--     du flux sans que personne n'ait à penser à couper l'abonnement.
--
-- Une caserne **suspendue** continue, elle, d'alimenter le flux :
-- `docs/PRD.md § 6.6` dit « suspendu : lecture seule pour tous », et un flux
-- calendrier est une lecture. Le vider ferait croire à des gardes annulées, ce
-- qui est le contraire de ce que le produit promet quand il dit que rien n'est
-- supprimé pour cause d'impayé. `station_writable()` n'apparaît donc pas ici.
--
-- Pourquoi une fonction SQL plutôt que douze requêtes depuis l'Edge Function
-- -------------------------------------------------------------------------
-- Même raison qu'en `0027` : la définition de « ce que ce membre a le droit de
-- voir » est écrite **une fois**, à côté des politiques qu'elle recopie, et
-- `supabase/tests/export_ics_test.sql` la vérifie à chaque PR — y compris en CI,
-- où les Edge Functions ne sont pas joignables. L'Edge Function ne fait plus
-- que de la mise en forme RFC 5545.

-- ===========================================================================
-- 1. La colonne
-- ===========================================================================
-- 24 octets tirés au sort, rendus en hexadécimal : 48 caractères sûrs dans une
-- URL, 192 bits d'entropie. Exactement la forme d'`invitations.token` (`0002`),
-- et pour la même raison — c'est un porteur de droits, pas un identifiant.
--
-- `not null default` plutôt qu'une génération paresseuse : un membre qui ouvre
-- son profil doit y trouver son adresse, pas un bouton « créer le lien » qui
-- ajoute une étape à un geste déjà rare. La valeur ne coûte rien tant qu'elle
-- n'est pas lue, et elle n'est lisible que par son porteur (§ 2).
alter table profiles
  add column ics_token text not null default encode(extensions.gen_random_bytes(24), 'hex');

-- L'unicité n'est pas décorative : c'est elle qui fait du jeton une **clé de
-- recherche**, donc qui garantit qu'un flux ne peut pas désigner deux personnes.
create unique index profiles_ics_token_uniq on profiles (ics_token);

comment on column profiles.ics_token is
  'Secret d''abonnement au flux calendrier (ticket 028). Porteur de droits : hors du grant de colonne d''anon et d''authenticated, lisible par son seul porteur via my_ics_token(), régénérable par rotate_ics_token(). Absent de l''export RGPD (0027, liste blanche explicite) : un jeton recopié dans un fichier qui voyage est un jeton compromis.';

-- ===========================================================================
-- 2. Le jeton n'est lisible par personne d'autre, pas même dans sa caserne
-- ===========================================================================
-- `profiles_select_self_or_same_station` (`0007`) ouvre la ligne `profiles` de
-- chaque membre à **tous** les membres de sa caserne — c'est ce qui permet
-- d'afficher un nom dans un planning. La RLS raisonne par ligne ; elle n'a aucun
-- moyen d'excepter une colonne. Sans ce qui suit, n'importe quel collègue lirait
-- le jeton d'abonnement de n'importe qui et s'abonnerait à ses astreintes.
--
-- C'est le mécanisme d'`invitations.token` en `0008`, appliqué au même problème :
-- un `revoke` de table, puis un `grant` nommant les colonnes. `revoke` colonne
-- par colonne ne suffirait pas — un privilège de table couvre toutes les
-- colonnes, présentes et futures, et c'est justement ce qu'on retire.
revoke select, insert, update on profiles from anon, authenticated;

grant select (id, first_name, last_name, email, phone, push_enabled, locale,
              created_at, updated_at)
  on profiles to authenticated;

-- L'écriture est encore plus étroite que la lecture : un jeton **choisi** par le
-- client ne serait plus un secret tiré au sort. `email` n'y est pas non plus —
-- c'est l'identifiant de connexion, il se change chez GoTrue, pas ici
-- (`design/007-profil.md § 5.1`).
grant update (first_name, last_name, phone, push_enabled, locale)
  on profiles to authenticated;

-- `profiles_insert_self` reste (`0007`), mais elle ne porte plus que ce qu'un
-- profil neuf a le droit de déclarer. Le chemin nominal est de toute façon
-- `handle_new_user`, qui est `security definer` et ne passe pas par ces grants.
grant insert (id, first_name, last_name, email, phone, locale)
  on profiles to authenticated;

-- ===========================================================================
-- 3. my_ics_token / rotate_ics_token — les deux seuls chemins d'un client
-- ===========================================================================
-- Aucune des deux ne prend de paramètre, et c'est **la** règle de sécurité :
-- un `p_user_id` ici serait une porte pour lire — ou pour faire tourner —
-- l'abonnement de n'importe qui. L'identité vient d'`auth.uid()`, comme pour
-- `station_access` (`0024`).
create function my_ics_token() returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.ics_token from profiles p where p.id = auth.uid();
$$;

comment on function my_ics_token() is
  'Le jeton d''abonnement calendrier de l''appelant, et de personne d''autre (ticket 028). Null si le profil n''existe pas ou si l''appelant n''est pas authentifié.';

-- Régénérer, c'est révoquer : l'ancienne adresse cesse de désigner quelqu'un au
-- `commit`. Aucun sursis — un abonnement qu'on veut couper est un abonnement
-- qu'on veut couper maintenant.
--
-- `set ics_token = default` réévalue le défaut de la colonne : la forme du jeton
-- est définie **une seule fois**, au § 1, et la faire évoluer ne demandera pas de
-- retrouver une seconde copie de l'expression.
create function rotate_ics_token() returns text
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_token text;
begin
  if auth.uid() is null then
    return null;
  end if;

  update profiles set ics_token = default
   where id = auth.uid()
  returning ics_token into v_token;

  return v_token;
end $$;

comment on function rotate_ics_token() is
  'Tire un nouveau jeton d''abonnement calendrier pour l''appelant et invalide l''ancien sur-le-champ (ticket 028). Null si l''appelant n''est pas authentifié ou n''a pas de profil.';

revoke all on function my_ics_token()     from public, anon;
revoke all on function rotate_ics_token() from public, anon;
grant execute on function my_ics_token()     to authenticated;
grant execute on function rotate_ics_token() to authenticated;

-- ===========================================================================
-- 4. ics_feed_events — ce que le flux a le droit de contenir
-- ===========================================================================
-- Retour : `{"ok": true, "membre": uuid, "evenements": [...]}`, ou
-- `{"ok": false, "code": "unknown_token"}`. Jamais d'exception pour un refus
-- métier : l'Edge Function doit pouvoir répondre 404 sans lire une trace.
--
-- Les cinq filtres, et chacun recopie une politique de `0007` :
--   - `a.user_id = <porteur du jeton>`      → `assignments_select_own_published`
--   - `a.status = 'accepted'`               → le produit : un flux d'agenda ne
--     porte que des gardes tenues, pas des propositions en attente de réponse
--     (elles vivent dans l'écran du ticket 021, où l'on **répond**)
--   - `sc.status in ('published','validated')` → `shifts_select_member_published`
--   - `m.status = 'active'`                 → `is_member()`
--   - `sh.date >= p_reference - 90`         → voir plus bas
--
-- **Aucune jointure ne mène à une autre personne.** Pas de second `assignments`,
-- pas de `profiles` autre que le porteur, pas de `memberships` autre que la
-- sienne : l'identité d'un équipier n'a aucun chemin jusqu'à ce JSON. C'est la
-- même frontière qu'en `0027`, tenue par la forme de la requête plutôt que par
-- un filtre qu'on pourrait oublier d'écrire.
--
-- **Quatre-vingt-dix jours en arrière.** L'historique n'est jamais supprimé
-- (`docs/PRD.md § 7.6`), mais un agenda rapatrie le fichier entier à chaque
-- rafraîchissement, toutes les heures, pour tous les membres. Trois mois
-- couvrent « c'était quand, ma dernière garde ? » ; l'écran « Mes astreintes »
-- garde le reste. `p_reference` existe pour que le test puisse le prouver sans
-- fabriquer une date système.
--
-- Les heures sont celles de **chaque** caserne, lues créneau par créneau : un
-- membre de deux centres n'a pas les mêmes horaires des deux côtés, et
-- `stations.settings` n'est pas une constante du produit (`docs/SCHEMA.md § 2.1`).
create function ics_feed_events(p_token text, p_reference date default current_date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_user       uuid;
  v_evenements jsonb;
begin
  if p_token is null or btrim(p_token) = '' then
    return jsonb_build_object('ok', false, 'code', 'unknown_token');
  end if;

  select p.id into v_user from profiles p where p.ics_token = p_token;

  if v_user is null then
    return jsonb_build_object('ok', false, 'code', 'unknown_token');
  end if;

  select coalesce(jsonb_agg(ligne order by tri_date, tri_creneau), '[]'::jsonb)
    into v_evenements
  from (
    select sh.date as tri_date,
           sh.slot as tri_creneau,
           jsonb_build_object(
             'id',         a.id,
             'date',       sh.date,
             'creneau',    sh.slot,
             'caserne',    st.name,
             'fuseau',     st.timezone,
             'debut_jour', coalesce(st.settings ->> 'day_start', '07:00'),
             'fin_jour',   coalesce(st.settings ->> 'day_end',   '19:00'),
             'modifie_le', a.updated_at
           ) as ligne
      from assignments a
      join shifts    sh on sh.id = a.shift_id
      join schedules sc on sc.id = sh.schedule_id
      join stations  st on st.id = a.station_id
      join memberships m on m.station_id = a.station_id
                        and m.user_id    = a.user_id
     where a.user_id  = v_user
       and a.status   = 'accepted'
       and sc.status in ('published', 'validated')
       and m.status   = 'active'
       and sh.date   >= p_reference - 90
  ) t;

  return jsonb_build_object(
    'ok', true,
    'membre', v_user,
    'evenements', v_evenements
  );
end $$;

comment on function ics_feed_events(text, date) is
  'Le contenu du flux calendrier d''un membre, désigné par son jeton d''abonnement (ticket 028) : ses astreintes acceptées sur un planning publié ou validé, dans les casernes où il est encore actif, à partir de p_reference - 90 jours, avec le nom, le fuseau et les heures d''affichage de chaque caserne. Rien d''un autre membre, rien d''une autre caserne. Rend {"ok": false, "code": "unknown_token"} pour un jeton inconnu. Réservée au rôle de service : le jeton est un secret, pas un paramètre de client.';

-- Même verrou qu'`export_own_data` (`0027`) : une fonction dont le paramètre est
-- un porteur de droits n'a rien à faire dans l'API cliente. `revoke from public`
-- ne suffit pas — `api.auto_expose_new_tables` pose des grants nominatifs sur
-- anon et authenticated (voir `0009`).
revoke all on function ics_feed_events(text, date) from public, anon, authenticated;
grant execute on function ics_feed_events(text, date) to service_role;
