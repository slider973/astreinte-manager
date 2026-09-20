-- 0011 — Paramètres de la caserne : validation du document `settings`, garde-fou
-- sur le fuseau, recalcul des dates limites. Ticket 010.
-- Référence : docs/SCHEMA.md sections 2.1, 2.5, 2.9 et 5.
--
-- Ce que 0001 laisse passer
-- -------------------------
-- `stations.settings` est un `jsonb` avec un défaut juste et **aucune contrainte**.
-- Le commentaire de colonne dit « validé côté Edge Function et app » : tant qu'il
-- n'existe ni l'une ni l'autre, n'importe quel admin écrit n'importe quoi par
-- PostgREST — `{"required_day": "beaucoup"}`, `{"day_start": "25h"}`, une clé mal
-- orthographiée qui ne sera jamais lue. Les conséquences ne sont pas visibles au
-- moment de l'écriture : elles arrivent un mois plus tard, à la génération du
-- planning, sous la forme d'un cast qui explose ou d'un effectif à 1 alors que le
-- chef de centre croyait avoir écrit 2.
--
-- Un document libre en base sans contrainte est un champ texte : la validation
-- côté app ne protège que l'app. Elle est donc doublée ici, à l'endroit où la
-- donnée entre.
--
-- Trois choses sont posées :
--
--   1. `station_settings_valid(jsonb)` + contrainte `check` sur `stations` :
--      clés connues, clés obligatoires, types, bornes, format des heures, et la
--      structure des surcharges telle que la décrit docs/SCHEMA.md § 2.1.
--   2. Un garde-fou sur `stations.timezone` : un fuseau inconnu casserait le
--      calcul des dates limites, et le message de PostgreSQL arrive trop tard.
--   3. `periods.deadline_at` recalculée pour les périodes **encore ouvertes**
--      quand le jour limite ou le fuseau change (critère d'acceptation du ticket).
--
-- Ce qui n'est **pas** posé, volontairement : rien ne touche `shifts.required_count`.
-- C'est l'autre critère du ticket — « changer l'effectif requis n'affecte que les
-- plannings créés ensuite » — et il est déjà vrai dans le schéma : `required_count`
-- est une colonne de `shifts` (§ 2.9), renseignée à la création du planning depuis
-- les settings du moment, puis indépendante. Le prouver est le rôle du test
-- (`supabase/tests/station_settings_test.sql`), pas d'une migration.

-- ===========================================================================
-- 1. Validation du document `settings`
-- ===========================================================================

-- Une heure d'affichage : la chaîne « HH:MM », de 00:00 à 23:59.
create function station_settings_heure_valide(p_valeur jsonb) returns boolean
language sql immutable
set search_path = public, pg_temp
as $$
  select jsonb_typeof(p_valeur) = 'string'
     and (p_valeur #>> '{}') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$';
$$;

comment on function station_settings_heure_valide(jsonb) is
  'Vrai si le jsonb est une chaîne « HH:MM » valide (00:00 à 23:59).';

-- Un entier borné. `jsonb_typeof` dit « number » pour 2 comme pour 2.5 : le
-- texte du nombre est donc relu, sans quoi un effectif de 1.5 passerait et
-- serait tronqué au cast.
create function station_settings_entier_valide(
  p_valeur jsonb, p_min integer, p_max integer
) returns boolean
language sql immutable
set search_path = public, pg_temp
as $$
  select jsonb_typeof(p_valeur) = 'number'
     and (p_valeur #>> '{}') ~ '^-?[0-9]+$'
     and (p_valeur #>> '{}')::bigint between p_min and p_max;
$$;

comment on function station_settings_entier_valide(jsonb, integer, integer) is
  'Vrai si le jsonb est un entier (sans partie décimale) compris entre p_min et p_max.';

-- Une clé de surcharge : soit un jour de semaine, soit une date ISO réelle.
-- La date est vérifiée par `make_date` plutôt que par un cast : le cast
-- text -> date dépend de `DateStyle` (donc pas immuable), et un simple motif
-- accepterait le 31 février.
create function station_settings_cle_surcharge_valide(p_cle text) returns boolean
language plpgsql immutable
set search_path = public, pg_temp
as $$
declare
  jours constant text[] := array['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  ignore date;
begin
  if p_cle = any (jours) then return true; end if;
  if p_cle !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then return false; end if;

  begin
    ignore := make_date(
      substring(p_cle from 1 for 4)::int,
      substring(p_cle from 6 for 2)::int,
      substring(p_cle from 9 for 2)::int
    );
  exception
    when others then return false;
  end;
  return true;
end $$;

comment on function station_settings_cle_surcharge_valide(text) is
  'Vrai pour « mon » … « sun » ou pour une date ISO réelle (docs/SCHEMA.md § 2.1).';

-- Le document entier. Appelée par la contrainte `check` de `stations`, et
-- doublée à l'identique côté application (lib/features/parametres/domain/).
create function station_settings_valid(p_settings jsonb) returns boolean
language plpgsql immutable
set search_path = public, pg_temp
as $$
declare
  -- Liste blanche : une clé inconnue est une faute de frappe qui ne sera
  -- jamais lue. Mieux vaut la refuser à l'écriture que la découvrir au
  -- planning suivant.
  connues constant text[] := array[
    'day_start', 'day_end',
    'required_day', 'required_night', 'required_overrides',
    'availability_deadline_day',
    'response_reminder_hours', 'response_email_hours', 'late_report_hours'
  ];
  obligatoires constant text[] := array[
    'day_start', 'day_end',
    'required_day', 'required_night',
    'availability_deadline_day',
    'response_reminder_hours', 'response_email_hours', 'late_report_hours'
  ];
  -- 50 pompiers sur un créneau : au-delà, c'est une faute de frappe.
  effectif_max constant integer := 50;
  -- 28 : le jour limite doit exister dans tous les mois, février compris.
  jour_limite_max constant integer := 28;
  -- 336 heures = deux semaines. Un délai de relance au-delà ne relance plus.
  delai_max constant integer := 336;
  cle text;
  surcharge jsonb;
  sous_cle text;
begin
  if p_settings is null or jsonb_typeof(p_settings) <> 'object' then
    return false;
  end if;

  for cle in select jsonb_object_keys(p_settings) loop
    if not (cle = any (connues)) then return false; end if;
  end loop;

  foreach cle in array obligatoires loop
    if not (p_settings ? cle) then return false; end if;
  end loop;

  if not station_settings_heure_valide(p_settings -> 'day_start')
     or not station_settings_heure_valide(p_settings -> 'day_end') then
    return false;
  end if;

  -- Un créneau de jour de zéro minute n'est pas un affichage, c'est une
  -- coquille : 07:00 – 07:00 ne dit rien à personne.
  if (p_settings ->> 'day_start') = (p_settings ->> 'day_end') then
    return false;
  end if;

  if not station_settings_entier_valide(p_settings -> 'required_day', 0, effectif_max)
     or not station_settings_entier_valide(p_settings -> 'required_night', 0, effectif_max) then
    return false;
  end if;

  if not station_settings_entier_valide(
       p_settings -> 'availability_deadline_day', 1, jour_limite_max) then
    return false;
  end if;

  if not station_settings_entier_valide(p_settings -> 'response_reminder_hours', 1, delai_max)
     or not station_settings_entier_valide(p_settings -> 'response_email_hours', 1, delai_max)
     or not station_settings_entier_valide(p_settings -> 'late_report_hours', 1, delai_max) then
    return false;
  end if;

  -- `required_overrides` est facultatif. Présent, il est un objet dont chaque
  -- entrée est {"day": n} et/ou {"night": n} — forme de docs/SCHEMA.md § 2.1 :
  -- {"sat": {"day": 2}, "2026-12-31": {"night": 3}}.
  if p_settings ? 'required_overrides' then
    if jsonb_typeof(p_settings -> 'required_overrides') <> 'object' then
      return false;
    end if;

    for cle, surcharge in
      select * from jsonb_each(p_settings -> 'required_overrides')
    loop
      if not station_settings_cle_surcharge_valide(cle) then return false; end if;
      if jsonb_typeof(surcharge) <> 'object' then return false; end if;

      -- Une surcharge vide ne surcharge rien : elle laisse croire à une règle.
      if surcharge = '{}'::jsonb then return false; end if;

      for sous_cle in select jsonb_object_keys(surcharge) loop
        if sous_cle not in ('day', 'night') then return false; end if;
        if not station_settings_entier_valide(
             surcharge -> sous_cle, 0, effectif_max) then
          return false;
        end if;
      end loop;
    end loop;
  end if;

  return true;
end $$;

comment on function station_settings_valid(jsonb) is
  'Valide le document stations.settings (docs/SCHEMA.md § 2.1). Support de la contrainte stations_settings_valide et miroir exact de la validation côté application.';

-- L'exécution reste ouverte à `authenticated` : la contrainte `check` est
-- évaluée sous l'identité de qui écrit, et une fonction non exécutable rendrait
-- toute mise à jour impossible. Ces quatre fonctions ne lisent aucune table et
-- ne révèlent rien — contrairement aux fonctions d'invitation (0009), dont
-- l'exécution est révoquée.

alter table stations
  add constraint stations_settings_valide check (station_settings_valid(settings));

-- Le nom est affiché aux membres et dans les courriels d'invitation : ni vide,
-- ni un roman.
alter table stations
  add constraint stations_name_non_vide
  check (btrim(name) <> '' and char_length(name) <= 80);

-- ===========================================================================
-- 2. Fuseau horaire : refusé s'il est inconnu
-- ===========================================================================
-- Sans ce garde-fou, un fuseau inventé s'écrit sans bruit et n'échoue qu'au
-- premier `make_timestamptz` — dans le cron de verrouillage, à 3 h du matin,
-- loin de l'écran qui l'a écrit. `pg_timezone_names` est lisible par tous ;
-- le déclencheur n'a donc rien à définir en `security definer`.
create function stations_check_timezone() returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if not exists (select 1 from pg_timezone_names where name = new.timezone) then
    raise exception 'station_timezone_unknown'
      using hint = 'Le fuseau horaire doit être un nom de la base IANA, par exemple Europe/Paris.';
  end if;
  return new;
end $$;

comment on function stations_check_timezone() is
  'Refuse un fuseau horaire absent de pg_timezone_names : il casserait le calcul des dates limites.';

revoke execute on function stations_check_timezone() from public, anon, authenticated;

create trigger stations_check_timezone
  before insert or update of timezone on stations
  for each row execute function stations_check_timezone();

-- ===========================================================================
-- 3. Date limite d'une période, et son recalcul
-- ===========================================================================

-- La règle, écrite une seule fois : le jour limite du mois **précédent**, à
-- 23:59:59, dans le fuseau de la caserne. C'est exactement le calcul que fait
-- déjà supabase/seed.sql ; il vit désormais dans la base, où le cron de
-- création des périodes (ticket 012) le réutilisera.
--
-- `least` avec le dernier jour du mois est une ceinture : la contrainte borne
-- déjà le jour limite à 28, mais une caserne créée avant cette migration peut
-- porter 31 dans son document.
create function period_deadline_at(
  p_year integer, p_month integer, p_deadline_day integer, p_timezone text
) returns timestamptz
language sql stable
set search_path = public, pg_temp
as $$
  select make_timestamptz(
    extract(year  from precedent)::int,
    extract(month from precedent)::int,
    least(
      greatest(p_deadline_day, 1),
      extract(day from (precedent + interval '1 month' - interval '1 day'))::int
    ),
    23, 59, 59,
    p_timezone
  )
  from (select (make_date(p_year, p_month, 1) - interval '1 month')::date as precedent) s;
$$;

comment on function period_deadline_at(integer, integer, integer, text) is
  'Date limite de saisie d''une période : le jour limite du mois précédent, 23:59:59, dans le fuseau de la caserne (docs/SCHEMA.md § 2.5).';

-- Le recalcul lui-même.
--
-- Pourquoi `security definer`, contrairement à `memberships_guard_admin` (0010) :
-- ici il n'y a pas de test « est-ce une écriture serveur ? » à fausser, et
-- `deadline_at` est une valeur **dérivée**, pas une décision d'administration.
-- Qui a le droit de changer le jour limite a été tranché par la politique
-- `stations_update_admin` ; laisser la RLS de `periods` rejouer l'arbitrage
-- aurait une conséquence absurde : `periods_update_admin` exige
-- `station_writable()`, alors que l'update de `stations` en est volontairement
-- dispensé (docs/SCHEMA.md § 4, « pour permettre de régulariser l'abonnement »).
-- Une caserne suspendue verrait donc sa modification de jour limite échouer, ou
-- pire, réussir en laissant des dates limites fausses derrière elle.
--
-- Le périmètre est fermé par construction : le déclencheur ne touche que les
-- périodes de la caserne dont la ligne vient d'être écrite, et n'écrit qu'une
-- valeur calculée.
create function stations_recalcule_deadlines() returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  jour integer := (new.settings ->> 'availability_deadline_day')::int;
  deplacees integer := 0;
begin
  -- Seules les périodes encore ouvertes bougent. Une période verrouillée a
  -- déjà produit son planning : lui réécrire sa date limite réécrirait
  -- l'histoire.
  if (old.settings ->> 'availability_deadline_day')
       is distinct from (new.settings ->> 'availability_deadline_day')
     or old.timezone is distinct from new.timezone then

    update periods p
       set deadline_at = period_deadline_at(p.year, p.month, jour, new.timezone)
     where p.station_id = new.id
       and p.status = 'open'
       and p.deadline_at
           is distinct from period_deadline_at(p.year, p.month, jour, new.timezone);

    get diagnostics deplacees = row_count;
  end if;

  -- Qui a changé quoi, et ce que ça a déplacé. Un membre qui trouve son mois
  -- fermé plus tôt que prévu doit pouvoir être renseigné.
  insert into audit_log (station_id, actor_id, action, entity, entity_id, data)
  values (
    new.id,
    auth.uid(),
    'station.settings_updated',
    'station',
    new.id,
    jsonb_build_object(
      'avant', jsonb_build_object(
        'name', old.name, 'timezone', old.timezone, 'settings', old.settings),
      'apres', jsonb_build_object(
        'name', new.name, 'timezone', new.timezone, 'settings', new.settings),
      'periodes_deplacees', deplacees
    )
  );

  return null;
end $$;

comment on function stations_recalcule_deadlines() is
  'Après modification d''une caserne : recalcule periods.deadline_at des périodes ouvertes si le jour limite ou le fuseau a changé, et journalise le changement.';

revoke execute on function stations_recalcule_deadlines() from public, anon, authenticated;

create trigger stations_recalcule_deadlines
  after update on stations
  for each row
  when (
    old.settings is distinct from new.settings
    or old.timezone is distinct from new.timezone
    or old.name is distinct from new.name
  )
  execute function stations_recalcule_deadlines();
