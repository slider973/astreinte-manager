-- 0017 — La matrice des disponibilités de l'admin et la charge d'un membre.
-- Ticket 016. Référence : docs/SCHEMA.md sections 2.6, 2.7, 6, 9 et 10 ;
-- docs/PRD.md sections 5.3, 6.3 et 6.4.
--
-- Trois choses arrivent ici : le calendrier français en base, la vue de charge
-- `v_member_load`, et la fonction `availability_matrix`. Elles se tiennent, et
-- l'ordre n'est pas libre : la charge se compte en unités de weekend, et une
-- unité de weekend ne se définit pas sans les jours fériés.
--
--
-- 1. Pourquoi le calendrier descend en base
-- -----------------------------------------
-- Le compteur de weekends du pompier est calculé dans l'application depuis le
-- ticket 011 (`lib/core/l10n/jours_feries.dart`, `lib/features/dispos/domain/
-- disponibilite_mois.dart`). Le quota restant du chef de centre, lui, se compte
-- sur des attributions que l'application ne rapatrie pas : il doit se calculer
-- en base. Le même nombre est donc produit à deux endroits.
--
-- Deux chiffres différents pour la même chose, c'est la pire des pannes : rien
-- ne casse, personne ne le voit, et le planning se construit sur un quota faux.
-- La parité est donc **testée**, des deux côtés, contre un corpus unique :
-- `supabase/tests/matrice_admin_test.sql § 1` et
-- `test/core/l10n/jours_feries_parite_base_test.dart` portent la même table de
-- 15 années de fériés, et l'un des deux rougit dès que l'un des deux calculs
-- bouge. C'est cette table qui est la référence, pas l'un des deux codes.
--
-- Calculé, jamais tabulé — comme côté application, et pour la même raison : une
-- table de fériés sur trois ans périme en silence. L'application ouvre des mois
-- deux mois à l'avance, indéfiniment ; le jour où la table s'arrête, un weekend
-- disparaît du compteur sans qu'aucune requête n'échoue. Le comput de Pâques
-- (Meeus/Butcher, grégorien) tient en quinze lignes et vaut jusqu'en 4099.
--
-- Les fériés d'Alsace-Moselle (Vendredi saint, 26 décembre) ne sont pas traités,
-- exactement comme côté application : ce serait un réglage de caserne, il
-- n'existe pas au schéma.
--
--
-- 2. Pourquoi la matrice rend une ligne par membre et non une ligne par cellule
-- ----------------------------------------------------------------------------
-- `docs/SCHEMA.md § 6` annonçait « une ligne par (membre actif, date, créneau) ».
-- Écart assumé, et le document est corrigé dans le même commit.
--
-- La cible du produit est 60 membres × 31 jours × 2 créneaux = 3 720 cellules,
-- affichées en moins de deux secondes sur une PWA, parfois en 4G au bord d'une
-- route. Une ligne par cellule en PostgREST, c'est 3 720 objets JSON qui
-- répètent chacun l'identifiant du membre, la date et le créneau :
--
--     {"user_id":"aaaaaaaa-0000-4000-8000-000000000101",
--      "date":"2026-10-01","slot":"day","status":"available"}
--
-- soit ~110 octets par cellule, ~410 ko sur le fil, et 3 720 `Map<String,
-- dynamic>` à construire puis à réindexer en mémoire côté Dart. Le coût n'est
-- pas dans Postgres, il est dans le transport et dans `jsonDecode`.
--
-- Une ligne par membre, avec le mois encodé en deux chaînes de longueur fixe —
-- un caractère par jour, une chaîne pour le jour, une pour la nuit — c'est 60
-- objets, ~2 × 31 caractères de grille chacun, ~20 ko au total. Vingt fois
-- moins, et surtout : l'accès à une cellule devient `jours[jour - 1]`, un index
-- de chaîne, au lieu d'une recherche dans une table de hachage construite au
-- chargement. Une grille qui se peint cellule par cellule à chaque image a tout
-- intérêt à ce que la lecture d'une cellule soit un accès direct.
--
-- L'alphabet est volontairement minuscule, trois états et pas un de plus,
-- exactement ceux de `docs/SCHEMA.md § 2.6` :
--
--     '.' non saisi (absence de ligne)   'D' disponible   'A' absent
--     Minuscules 'd' et 'a' : même état, mais saisi par un admin à la place du
--     membre. L'écran les distingue ; la valeur de disponibilité est la même.
--
-- La position `i` (0 en tête) est le jour `i + 1` du mois ; la longueur des deux
-- chaînes est le nombre de jours du mois, ce que le test vérifie sur un mois de
-- 28, de 30 et de 31 jours. Pas de date à analyser, pas de fuseau, pas de clé
-- composée : la seule chose qu'un client puisse se tromper à faire, c'est de
-- décaler d'un, et c'est visible à l'œil sur la première colonne.
--
-- Le prix de ce choix est l'opacité : une chaîne `..D.AD..` ne se lit pas dans
-- un inspecteur réseau aussi bien qu'un objet nommé. C'est un prix acceptable
-- pour un écran d'administration dont le contrat tient en trois caractères.
--
--
-- 3. Ce que la matrice ne fait pas
-- --------------------------------
-- Elle ne **saisit** pas. L'admin qui touche une cellule écrit dans
-- `availabilities` par l'upsert habituel : les politiques `availabilities_*_admin`
-- (0007, durcies en 0008) l'autorisent déjà sur toute sa caserne, et le
-- déclencheur `availabilities_trace_auteur` (0012) impose `set_by = auth.uid()`
-- sans qu'aucun client ait à y penser. Ajouter une RPC d'écriture ici
-- n'apporterait qu'un second chemin à garder juste.

-- ===========================================================================
-- 1. Le calendrier français, calculé
-- ===========================================================================

-- Dimanche de Pâques, comput grégorien de Meeus/Butcher (valable 1583–4099).
--
-- Ce n'est pas un jour férié en France — il tombe un dimanche — mais les trois
-- fériés mobiles s'en déduisent : lundi de Pâques = +1, Ascension = +39, lundi
-- de Pentecôte = +50. Transcription ligne à ligne de `paquesGregorien`
-- (`lib/core/l10n/jours_feries.dart`) : les divisions sont entières des deux
-- côtés (`~/` en Dart, `/` sur des `integer` en SQL) et toutes les valeurs
-- intermédiaires sont positives pour les années qui nous concernent, donc le
-- sens de troncature n'a pas à être discuté.
create function paques_gregorien(p_annee integer) returns date
language plpgsql
immutable
strict
parallel safe
set search_path = public, pg_temp
as $$
declare
  a integer := p_annee % 19;
  b integer := p_annee / 100;
  c integer := p_annee % 100;
  d integer := b / 4;
  e integer := b % 4;
  f integer := (b + 8) / 25;
  g integer := (b - f + 1) / 3;
  h integer := (19 * a + b - d - g + 15) % 30;
  i integer := c / 4;
  k integer := c % 4;
  l integer;
  m integer;
  numerateur integer;
begin
  l := (32 + 2 * e + 2 * i - h - k) % 7;
  m := (a + 11 * h + 22 * l) / 451;
  numerateur := h + l - 7 * m + 114;
  return make_date(p_annee, numerateur / 31, numerateur % 31 + 1);
end $$;

comment on function paques_gregorien(integer) is
  'Dimanche de Pâques (comput grégorien de Meeus/Butcher). Même calcul que paquesGregorien() dans lib/core/l10n/jours_feries.dart.';

-- Les onze jours fériés français métropolitains d'une année.
-- Huit à date fixe, trois adossés à Pâques. Même liste que `_calculer()` côté
-- application, dans le même ordre de définition.
create function jours_feries_fr(p_annee integer) returns date[]
language sql
immutable
strict
parallel safe
set search_path = public, pg_temp
as $$
  select array[
    make_date(p_annee,  1,  1),                            -- Jour de l'an
    paques_gregorien(p_annee) + 1,                         -- Lundi de Pâques
    make_date(p_annee,  5,  1),                            -- Fête du Travail
    make_date(p_annee,  5,  8),                            -- Victoire 1945
    paques_gregorien(p_annee) + 39,                        -- Ascension
    paques_gregorien(p_annee) + 50,                        -- Lundi de Pentecôte
    make_date(p_annee,  7, 14),                            -- Fête nationale
    make_date(p_annee,  8, 15),                            -- Assomption
    make_date(p_annee, 11,  1),                            -- Toussaint
    make_date(p_annee, 11, 11),                            -- Armistice 1918
    make_date(p_annee, 12, 25)                             -- Noël
  ];
$$;

comment on function jours_feries_fr(integer) is
  'Les onze jours fériés français métropolitains d''une année, calculés et non tabulés. Miroir de joursFeriesDeLAnnee() côté application. Alsace-Moselle non traitée (ce serait un réglage de caserne, absent du schéma).';

-- Écrite pour être appelée **par ligne**, ce qui change tout.
--
-- La forme évidente — `p_date = any (jours_feries_fr(année))` — construit les
-- onze dates de l'année à chaque appel, donc calcule Pâques **trois fois** (les
-- trois fériés mobiles), donc paye trois invocations de `paques_gregorien` pour
-- répondre « non » à un mardi de novembre. Mesuré : 110 ms pour 3 720 appels,
-- soit 30 µs par date, et c'était à soi seul la moitié du coût de la matrice de
-- soixante membres (`supabase/tests/matrice_admin_test.sql § 6`).
--
-- L'ordre ci-dessous renverse le raisonnement : huit des onze fériés sont à date
-- fixe et se reconnaissent à une comparaison d'entiers ; les trois autres, tous
-- adossés à Pâques, ne peuvent tomber qu'entre le 23 mars et le 14 juin (lundi
-- de Pâques au plus tôt, lundi de Pentecôte au plus tard, Pâques grégorienne
-- allant du 22 mars au 25 avril). Hors de cette fenêtre — les trois quarts de
-- l'année — la réponse est connue sans comput. Mesuré : 16 ms pour les mêmes
-- 3 720 appels, 6,8 fois moins.
--
-- Le prix de cette accélération est que la liste des fériés est maintenant
-- écrite à deux endroits, ici et dans `jours_feries_fr`. C'est exactement la
-- faute que cette migration reproche au reste du monde, et elle n'est tolérable
-- que parce qu'elle est **vérifiée** : le test compare les deux formes jour par
-- jour de 1900 à 2100, soit 73 414 dates, et refuse le moindre désaccord.
create function est_jour_ferie(p_date date) returns boolean
language plpgsql
immutable
strict
parallel safe
set search_path = public, pg_temp
as $$
declare
  -- Mois × 100 + jour : « 1225 » se lit Noël, et se compare en un cycle.
  mois_jour integer := extract(month from p_date)::integer * 100
                     + extract(day   from p_date)::integer;
  paques    date;
begin
  -- Les huit fériés à date fixe.
  if mois_jour in (101,   -- Jour de l'an
                   501,   -- Fête du Travail
                   508,   -- Victoire 1945
                   714,   -- Fête nationale
                   815,   -- Assomption
                   1101,  -- Toussaint
                   1111,  -- Armistice 1918
                   1225)  -- Noël
  then
    return true;
  end if;

  -- Hors de la fenêtre des fériés mobiles : inutile de calculer Pâques.
  if mois_jour < 322 or mois_jour > 614 then
    return false;
  end if;

  paques := paques_gregorien(extract(year from p_date)::integer);
  return p_date in (paques + 1,    -- Lundi de Pâques
                    paques + 39,   -- Ascension
                    paques + 50);  -- Lundi de Pentecôte
end $$;

comment on function est_jour_ferie(date) is
  'Vrai si la date est un jour férié français métropolitain. Miroir de estJourFerie() côté application. Écrite pour l''appel par ligne : les huit fériés fixes d''abord, Pâques seulement dans sa fenêtre (23 mars – 14 juin). L''accord avec jours_feries_fr est vérifié jour par jour de 1900 à 2100 par le test.';

-- L'unité de weekend à laquelle appartient une date, ou NULL.
--
-- Les trois règles du client (docs/PRD.md § 6.3, tranchées au brief du ticket
-- 011 § 6.4 et figées dans `uniteWeekend()`) :
--
--   1. samedi et dimanche d'une même semaine forment **une seule** unité,
--      désignée par la date de son samedi — ce qui la rend unique même quand le
--      dimanche appartient à un autre mois ;
--   2. un jour férié du lundi au vendredi forme à lui seul une unité ;
--   3. un férié tombant un samedi ou un dimanche **ne double pas** l'unité : il
--      se fond dans celle du weekend. C'est l'ordre des tests qui le dit, la
--      règle 1 est examinée avant la règle 2.
--
-- `isodow` et non `dow` : 6 = samedi, 7 = dimanche, sans zéro ambigu. Sur un
-- `date`, l'extraction est immuable — sur un `timestamptz` elle ne le serait
-- pas, et c'est une des raisons pour lesquelles une astreinte est une date et
-- jamais un instant (docs/SCHEMA.md, préambule).
create function unite_weekend(p_date date) returns date
language sql
immutable
strict
parallel safe
set search_path = public, pg_temp
as $$
  select case extract(isodow from p_date)
    when 6 then p_date
    when 7 then p_date - 1
    else case when est_jour_ferie(p_date) then p_date end
  end;
$$;

comment on function unite_weekend(date) is
  'L''unité de weekend d''une date (samedi de son weekend, ou le jour lui-même si férié en semaine), NULL sinon. Miroir exact de uniteWeekend() dans lib/features/dispos/domain/disponibilite_mois.dart : la parité est testée des deux côtés contre un corpus commun.';

-- Fonctions pures, sans lecture de table : leur exécution reste ouverte. Un
-- client qui voudrait afficher les fériés d'un mois n'a de toute façon pas
-- besoin de la base pour ça, il les calcule déjà.
grant execute on function paques_gregorien(integer) to authenticated, anon;
grant execute on function jours_feries_fr(integer) to authenticated, anon;
grant execute on function est_jour_ferie(date)     to authenticated, anon;
grant execute on function unite_weekend(date)      to authenticated, anon;

-- ===========================================================================
-- 2. v_member_load — la charge d'un membre sur un mois
-- ===========================================================================
-- Une ligne par (caserne, membre actif, période). Toujours une ligne, même sans
-- aucune attribution et sans aucune préférence : l'en-tête de ligne de la
-- matrice doit pouvoir écrire « 0/3 astreintes » aussi bien que « illimité ».
--
-- Les colonnes, et ce qu'elles veulent dire :
--
--   shifts_count      astreintes **proposées ou acceptées** du mois. Une
--                     proposition consomme du quota : elle est en attente de
--                     réponse, pas annulée. `declined`, `replaced` et
--                     `cancelled` ne comptent pas (docs/SCHEMA.md § 2.10).
--   weekend_units     unités de weekend distinctes couvertes par ces mêmes
--                     astreintes, au sens de `unite_weekend` ci-dessus. Les
--                     jours ordinaires y rendent NULL, que `count(distinct)`
--                     ignore : quatre créneaux d'un même weekend comptent pour
--                     un, et c'est toute la règle du client.
--   max_shifts        plafonds déclarés par le membre pour ce mois
--   max_weekends      (`availability_preferences`, NULL = illimité).
--   shifts_left       plafond moins charge. **NULL quand le plafond est NULL** :
--   weekends_left     un illimité n'a pas de reste, et rendre 0 ferait griser un
--                     membre qui n'a rien demandé. La valeur peut être
--                     **négative** — le PRD § 5.3 autorise explicitement l'admin
--                     à dépasser un quota avec avertissement, et « -1 » est
--                     l'information dont il a besoin, pas « 0 ».
--   accepted_previous astreintes **acceptées** sur les trois mois précédents.
--                     C'est le second critère de tri des candidats
--                     (docs/PRD.md § 5.3 et § 6.4) et l'entrée de l'équilibrage
--                     de la proposition automatique (tickets 017 et 018).
--
-- « Les trois périodes précédentes » se lit ici « les trois mois calendaires
-- précédents », et c'est volontaire : une caserne qui n'aurait pas ouvert le
-- mois de juillet n'a pas pour autant vu ses pompiers d'astreinte disparaître,
-- et faire dépendre un historique d'attributions de l'existence de lignes dans
-- `periods` le rendrait faux au premier trou. Les attributions, elles, pendent
-- de `shifts.date`, qui existe toujours.
--
-- Seules les attributions de **la même caserne** comptent. Un pompier peut
-- servir dans deux casernes (docs/PRD.md § 6.1) ; le chef de centre de l'une
-- n'a ni à voir ni à compter les astreintes de l'autre.
--
-- `security_invoker`, comme `v_member_last_availability` (0010) et
-- `v_period_completion` (0013) : la vue n'accorde aucun droit.
--   - un **admin** lit tout de sa caserne : les nombres sont justes, c'est son
--     écran ;
--   - un **membre** voit les lignes des autres membres (il lit déjà
--     `memberships`) mais toutes leurs mesures à zéro et tous leurs plafonds à
--     NULL : `availability_preferences` et `assignments` ne lui montrent que
--     lui-même. Vue partielle, pas fuite — il n'apprend rien qu'il ne puisse
--     déjà lire ligne à ligne, et c'est vérifié par le test § 5 ;
--   - `anon` n'a aucune politique et ne lit rien.
create view v_member_load
with (security_invoker = true) as
  select
    p.station_id                             as station_id,
    m.user_id                                as user_id,
    p.id                                     as period_id,
    p.year                                   as year,
    p.month                                  as month,
    coalesce(charge.shifts_count, 0)::integer   as shifts_count,
    coalesce(charge.weekend_units, 0)::integer  as weekend_units,
    prefs.max_shifts                         as max_shifts,
    prefs.max_weekends                       as max_weekends,
    (prefs.max_shifts   - coalesce(charge.shifts_count, 0))::integer  as shifts_left,
    (prefs.max_weekends - coalesce(charge.weekend_units, 0))::integer as weekends_left,
    coalesce(histo.accepted_previous, 0)::integer as accepted_previous
  from periods p
  join memberships m
    on m.station_id = p.station_id
   and m.status = 'active'
  left join availability_preferences prefs
    on prefs.period_id = p.id
   and prefs.user_id = m.user_id
   and prefs.station_id = p.station_id
  left join lateral (
    select
      count(*)                              as shifts_count,
      count(distinct unite_weekend(s.date)) as weekend_units
    from assignments a
    join shifts s on s.id = a.shift_id and s.station_id = p.station_id
    where a.user_id = m.user_id
      and a.station_id = p.station_id
      and a.status in ('proposed', 'accepted')
      and s.date >= make_date(p.year, p.month, 1)
      and s.date <  (make_date(p.year, p.month, 1) + interval '1 month')::date
  ) charge on true
  left join lateral (
    select count(*) as accepted_previous
    from assignments a
    join shifts s on s.id = a.shift_id and s.station_id = p.station_id
    where a.user_id = m.user_id
      and a.station_id = p.station_id
      and a.status = 'accepted'
      and s.date >= (make_date(p.year, p.month, 1) - interval '3 months')::date
      and s.date <  make_date(p.year, p.month, 1)
  ) histo on true;

comment on view v_member_load is
  'Par (caserne, membre actif, période) : astreintes proposées ou acceptées, unités de weekend couvertes, plafonds déclarés, plafonds restants (NULL si illimité, négatifs si dépassés) et astreintes acceptées sur les trois mois précédents. security_invoker : juste pour un admin, partielle pour un membre.';

revoke all on v_member_load from anon;
grant select on v_member_load to authenticated;

-- ===========================================================================
-- 3. availability_matrix — la matrice d'un mois
-- ===========================================================================
-- `security definer` et non une vue lue sous la RLS de l'appelant : la matrice
-- est un écran d'administration, et le dire une fois, en haut de la fonction,
-- vaut mieux que de le laisser déduire d'un `is_admin(station_id)` réévalué sur
-- chacune des lignes d'`availabilities` du mois. Un membre ordinaire reçoit
-- `forbidden`, comme sur `create_period` (0012) — pas une matrice d'une seule
-- ligne, qui laisserait croire que l'écran lui est ouvert.
--
-- Rien n'y est interpolé, `search_path` figé, `pg_temp` nommé en dernier (0008).
create function availability_matrix(p_station uuid, p_period uuid)
returns table (
  user_id           uuid,
  display_name      text,
  first_name        text,
  last_name         text,
  comment           text,
  max_shifts        integer,
  max_weekends      integer,
  shifts_count      integer,
  weekend_units     integer,
  shifts_left       integer,
  weekends_left     integer,
  accepted_previous integer,
  day_slots         text,
  night_slots       text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  periode   periods;
  premier   date;
  suivant   date;
begin
  if not is_admin(p_station) then
    raise exception 'forbidden'
      using hint = 'La matrice des disponibilités est un écran d''administration de la caserne.';
  end if;

  select * into periode from periods where id = p_period and station_id = p_station;
  if periode.id is null then
    raise exception 'period_not_found'
      using hint = 'Cette période n''existe pas ou n''appartient pas à cette caserne.';
  end if;

  premier := make_date(periode.year, periode.month, 1);
  suivant := (premier + interval '1 month')::date;

  return query
  with membres as (
    -- Les membres **actifs** seulement : un pompier désactivé n'est pas
    -- attribuable, sa ligne n'a rien à faire dans la grille de construction.
    select
      m.user_id,
      coalesce(nullif(btrim(m.display_name), ''),
               btrim(pr.first_name || ' ' || pr.last_name)) as affiche,
      pr.first_name,
      pr.last_name
    from memberships m
    join profiles pr on pr.id = m.user_id
    where m.station_id = p_station and m.status = 'active'
  ),
  jours as (
    select
      j::date                       as jour,
      (j::date - premier + 1)::int  as rang
    from generate_series(premier, suivant - 1, interval '1 day') j
  ),
  -- Une seule lecture d'`availabilities` pour tout le mois et toute la caserne,
  -- servie par l'index `availabilities (station_id, date)` de 0003. À 60
  -- membres remplis, c'est ~3 700 lignes, une bagatelle ; ce qui compte, c'est
  -- qu'il n'y en ait qu'une, et non une par membre.
  saisies as (
    select
      a.user_id,
      a.date,
      a.slot,
      -- Majuscule quand le membre a saisi lui-même, minuscule quand un admin a
      -- saisi à sa place. La marque « saisi par l'admin » de l'écran survit ainsi
      -- au rechargement : sans elle, elle ne vivrait que dans la session qui a
      -- fait la saisie, et l'admin suivant ne verrait plus qui a écrit quoi.
      -- `set_by` est posé par le déclencheur `availabilities_trace_auteur` (0012)
      -- et vaut `null` sur les lignes antérieures, traitées comme saisies par le
      -- membre — le cas le plus probable et le moins alarmant des deux.
      case
        when a.set_by is not null and a.set_by <> a.user_id
          then case a.status when 'available' then 'd' else 'a' end
        else case a.status when 'available' then 'D' else 'A' end
      end as code
    from availabilities a
    where a.station_id = p_station
      and a.date >= premier
      and a.date <  suivant
  ),
  grille as (
    select
      mb.user_id,
      string_agg(coalesce(sj.code, '.'), '' order by j.rang) as day_slots,
      string_agg(coalesce(sn.code, '.'), '' order by j.rang) as night_slots
    from membres mb
    cross join jours j
    left join saisies sj
      on sj.user_id = mb.user_id and sj.date = j.jour and sj.slot = 'day'
    left join saisies sn
      on sn.user_id = mb.user_id and sn.date = j.jour and sn.slot = 'night'
    group by mb.user_id
  )
  select
    mb.user_id,
    mb.affiche,
    mb.first_name,
    mb.last_name,
    -- Le commentaire du mois que le membre a écrit au ticket 013. L'admin le
    -- lit ici : c'est la moitié utile d'un quota (« pas plus d'un weekend,
    -- garde des enfants »), et la faire chercher dans un second écran
    -- reviendrait à ne jamais la lire.
    prefs.comment,
    charge.max_shifts,
    charge.max_weekends,
    charge.shifts_count,
    charge.weekend_units,
    charge.shifts_left,
    charge.weekends_left,
    charge.accepted_previous,
    g.day_slots,
    g.night_slots
  from membres mb
  join grille g on g.user_id = mb.user_id
  left join availability_preferences prefs
    on prefs.station_id = p_station
   and prefs.period_id = p_period
   and prefs.user_id = mb.user_id
  -- Les quotas de l'écran **sont** ceux de `v_member_load`, ils n'en sont pas
  -- une seconde écriture : c'est le critère d'acceptation du ticket 016, et la
  -- seule façon de le tenir durablement est de ne pas recopier le calcul.
  left join v_member_load charge
    on charge.station_id = p_station
   and charge.period_id = p_period
   and charge.user_id = mb.user_id
  order by mb.affiche, mb.user_id;
end $$;

comment on function availability_matrix(uuid, uuid) is
  'Matrice des disponibilités d''un mois pour un admin : une ligne par membre actif, le mois encodé en deux chaînes d''un caractère par jour (« . » non saisi, « D » disponible, « A » absent), les plafonds et restes de v_member_load, et le commentaire du mois. Lève forbidden si l''appelant n''est pas admin de la caserne.';

revoke execute on function availability_matrix(uuid, uuid) from public, anon;
grant  execute on function availability_matrix(uuid, uuid) to authenticated;

-- ===========================================================================
-- 4. Index : aucun n'est ajouté, et c'est le résultat d'une mesure
-- ===========================================================================
-- Ce qui existe couvre les deux objets de cette migration :
--
--   availabilities (station_id, date)         0003 — la grille du mois
--   memberships (station_id, status)          0002 — les lignes de la matrice
--   availability_preferences (station_id,
--     user_id, period_id) unique              0003 — plafonds et commentaire
--   shifts (station_id, date)                 0004 — les créneaux d'un mois
--   assignments (shift_id, user_id) partiel
--     where status in ('proposed','accepted') 0004 — l'attribution d'un créneau
--
-- Le dernier est un index **partiel** dont le prédicat contient exactement les
-- deux statuts que compte `v_member_load`, et `status = 'accepted'` l'implique :
-- l'historique des trois mois s'en sert aussi.
--
-- Ce qui manquait n'était pas un index mais un **prédicat**. Les deux jointures
-- latérales de la vue ci-dessus joignent `shifts` par sa clé primaire et
-- restreignent la date ; écrites sans `s.station_id = p.station_id`, elles ne
-- donnaient au planificateur aucune raison de se servir de `shifts (station_id,
-- date)` et il parcourait la table **entière**, toutes casernes confondues,
-- une fois par membre et par latérale. Sur la base de démonstration cela ne se
-- voit pas ; sur un projet partagé par cent casernes, c'est cent fois trop de
-- pages lues pour compter les astreintes d'un seul pompier. Le prédicat est
-- redondant du point de vue des données — la RLS de 0008 impose déjà que le
-- créneau et l'attribution soient de la même caserne — et déterminant du point
-- de vue du plan. Mesures dans `supabase/tests/matrice_admin_test.sql § 6`.
--
-- Un index `assignments (station_id, user_id, status)` a été essayé puis retiré :
-- le planificateur ne le choisit pas, et il a raison. Les deux latérales sont
-- bornées par une fenêtre de dates (un mois, trois mois), donc partir des
-- créneaux coûte un nombre de sondes constant dans le temps, là où partir des
-- attributions du pompier coûterait sa carrière entière. Un index que personne
-- ne lit reste un index que tout le monde écrit.
