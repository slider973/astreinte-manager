-- Tests de la matrice des disponibilités et de la charge d'un membre
-- (migration 0017, ticket 016).
-- Lancement : scripts/test_rls.sh (ou psql -v ON_ERROR_STOP=1 -f ce fichier).
--
-- Ce qui est vérifié, section par section
-- ---------------------------------------
-- 1. Le calendrier français en base **est** celui de l'application. Corpus
--    commun : les dates de Pâques du test Dart `test/core/l10n/jours_feries_test.dart`
--    et les quinze années de fériés que reprend, caractère pour caractère,
--    `test/core/l10n/jours_feries_parite_base_test.dart`. Si l'un des deux
--    calculs bouge, l'un des deux tests rougit. Et, en base, l'accord des deux
--    formes de `est_jour_ferie` sur deux siècles.
-- 2. L'unité de weekend : samedi + dimanche = une unité, férié en semaine = une
--    unité à lui seul, férié un samedi ou un dimanche = pas de doublon, et le
--    dimanche du 1er d'un mois rattaché au samedi du mois précédent.
-- 3. La forme de la matrice : une ligne par membre actif, deux chaînes d'un
--    caractère par jour, longueur = nombre de jours du mois (28, 29, 30, 31),
--    alphabet « . D A » plus « d a » pour une case saisie par un admin,
--    position = jour, et le commentaire du mois du membre.
-- 4. v_member_load : proposé + accepté, refusé exclu, unités de weekend au sens
--    du client, restes NULL quand le plafond est illimité et négatifs quand il
--    est dépassé, historique borné aux trois mois précédents, cloisonnement par
--    caserne pour un pompier qui sert dans deux centres.
-- 5. Les droits : un admin voit tout de sa caserne et rien de la caserne
--    voisine ; un membre n'obtient pas la matrice et ne lit dans v_member_load
--    rien de plus qu'aujourd'hui ; `anon` n'appelle rien.
-- 6. La performance, mesurée **sous le rôle de l'application** : 60 membres
--    × 31 jours × 2 créneaux, tous saisis, avec un mois d'attributions et trois
--    mois d'historique. Et la comparaison avec le rôle propriétaire, parce que
--    la fonction est `security definer` et que les deux ne sont pas la même
--    chose — sous `postgres`, elle sort par la porte du refus en 3 ms.
--
-- Méthode identique aux autres fichiers du dossier : pas de pgTAP, une exception
-- fait sortir psql avec un code non nul, le tout dans une transaction annulée.
--
-- Fixtures : une caserne « CIS Matrice » et une caserne voisine « CIS Voisine »
-- créées ici, sur l'année 2027 que le seed ne touche pas, plus la caserne A du
-- seed pour la section 5.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests_mat;

create function tests_mat.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

create function tests_mat.egal(p_obtenu anyelement, p_attendu anyelement, p_label text) returns void
language plpgsql as $$
begin
  if p_obtenu is distinct from p_attendu then
    raise exception 'ECHEC : % — obtenu [%], attendu [%]', p_label, p_obtenu, p_attendu;
  end if;
  raise notice '  ok   % = %', p_label, coalesce(p_obtenu::text, 'NULL');
end $$;

-- `refuse` : l'instruction doit lever l'erreur nommée, et pas une autre. Une
-- assertion qui se contente de « ça a échoué » passe encore le jour où la
-- fonction échoue pour une faute de frappe.
create function tests_mat.refuse(p_sql text, p_erreur text, p_label text) returns void
language plpgsql as $$
begin
  execute p_sql;
  raise exception 'ECHEC : % — aucune erreur levée, % attendue', p_label, p_erreur;
exception
  when insufficient_privilege then
    raise notice '  ok   % (refusé : %)', p_label, sqlerrm;
  when others then
    if sqlerrm <> p_erreur then
      raise exception 'ECHEC : % — erreur [%] au lieu de [%]', p_label, sqlerrm, p_erreur;
    end if;
    raise notice '  ok   % (%)', p_label, sqlerrm;
end $$;

grant usage on schema tests_mat to authenticated, anon;
grant execute on all functions in schema tests_mat to authenticated, anon;

\echo ''
\echo '=== Matrice des disponibilités et charge d''un membre (0017) ==='

-- ===========================================================================
-- 1. Le calendrier français : parité avec l'application
-- ===========================================================================
\echo ''
\echo '--- 1. Jours fériés : le même calcul qu''en Dart'
savepoint s1;

-- Dates de Pâques : exactement le corpus de `test/core/l10n/jours_feries_test.dart`
-- (référence Bureau des longitudes), bords compris — une Pâques de mars (2027,
-- 2029) et une Pâques tardive (2038, 25 avril).
do $$
declare
  attendu record;
begin
  for attendu in
    select * from (values
      (2026, date '2026-04-05'),
      (2027, date '2027-03-28'),
      (2028, date '2028-04-16'),
      (2029, date '2029-04-01'),
      (2030, date '2030-04-21'),
      (2038, date '2038-04-25')
    ) as t(annee, paques)
  loop
    perform tests_mat.egal(
      paques_gregorien(attendu.annee), attendu.paques,
      format('Pâques %s', attendu.annee));
  end loop;
end $$;

-- Les onze fériés, quinze années de suite. Ce bloc est le corpus partagé : le
-- test Dart `test/core/l10n/jours_feries_parite_base_test.dart` porte les mêmes
-- quinze chaînes. Elles ne se recopient pas d'un code à l'autre — elles sont la
-- référence des deux.
do $$
declare
  attendu record;
  calcule text;
begin
  for attendu in
    select * from (values
      (2026, '2026-01-01 2026-04-06 2026-05-01 2026-05-08 2026-05-14 2026-05-25 2026-07-14 2026-08-15 2026-11-01 2026-11-11 2026-12-25'),
      (2027, '2027-01-01 2027-03-29 2027-05-01 2027-05-06 2027-05-08 2027-05-17 2027-07-14 2027-08-15 2027-11-01 2027-11-11 2027-12-25'),
      (2028, '2028-01-01 2028-04-17 2028-05-01 2028-05-08 2028-05-25 2028-06-05 2028-07-14 2028-08-15 2028-11-01 2028-11-11 2028-12-25'),
      (2029, '2029-01-01 2029-04-02 2029-05-01 2029-05-08 2029-05-10 2029-05-21 2029-07-14 2029-08-15 2029-11-01 2029-11-11 2029-12-25'),
      (2030, '2030-01-01 2030-04-22 2030-05-01 2030-05-08 2030-05-30 2030-06-10 2030-07-14 2030-08-15 2030-11-01 2030-11-11 2030-12-25'),
      (2031, '2031-01-01 2031-04-14 2031-05-01 2031-05-08 2031-05-22 2031-06-02 2031-07-14 2031-08-15 2031-11-01 2031-11-11 2031-12-25'),
      (2032, '2032-01-01 2032-03-29 2032-05-01 2032-05-06 2032-05-08 2032-05-17 2032-07-14 2032-08-15 2032-11-01 2032-11-11 2032-12-25'),
      (2033, '2033-01-01 2033-04-18 2033-05-01 2033-05-08 2033-05-26 2033-06-06 2033-07-14 2033-08-15 2033-11-01 2033-11-11 2033-12-25'),
      (2034, '2034-01-01 2034-04-10 2034-05-01 2034-05-08 2034-05-18 2034-05-29 2034-07-14 2034-08-15 2034-11-01 2034-11-11 2034-12-25'),
      (2035, '2035-01-01 2035-03-26 2035-05-01 2035-05-03 2035-05-08 2035-05-14 2035-07-14 2035-08-15 2035-11-01 2035-11-11 2035-12-25'),
      (2036, '2036-01-01 2036-04-14 2036-05-01 2036-05-08 2036-05-22 2036-06-02 2036-07-14 2036-08-15 2036-11-01 2036-11-11 2036-12-25'),
      (2037, '2037-01-01 2037-04-06 2037-05-01 2037-05-08 2037-05-14 2037-05-25 2037-07-14 2037-08-15 2037-11-01 2037-11-11 2037-12-25'),
      (2038, '2038-01-01 2038-04-26 2038-05-01 2038-05-08 2038-06-03 2038-06-14 2038-07-14 2038-08-15 2038-11-01 2038-11-11 2038-12-25'),
      (2039, '2039-01-01 2039-04-11 2039-05-01 2039-05-08 2039-05-19 2039-05-30 2039-07-14 2039-08-15 2039-11-01 2039-11-11 2039-12-25'),
      (2040, '2040-01-01 2040-04-02 2040-05-01 2040-05-08 2040-05-10 2040-05-21 2040-07-14 2040-08-15 2040-11-01 2040-11-11 2040-12-25')
    ) as t(annee, feries)
  loop
    select string_agg(to_char(d, 'YYYY-MM-DD'), ' ' order by d)
      into calcule
      from unnest(jours_feries_fr(attendu.annee)) d;
    perform tests_mat.egal(calcule, attendu.feries, format('fériés %s', attendu.annee));
  end loop;
end $$;

do $$
begin
  -- Onze fériés distincts chaque année, tous dans l'année demandée : le
  -- pendant SQL du test Dart « 2026 à 2030 : onze fériés distincts ».
  for annee in 2026..2040 loop
    perform tests_mat.check(
      (select count(distinct d) from unnest(jours_feries_fr(annee)) d) = 11,
      format('%s : onze fériés distincts', annee));
    perform tests_mat.check(
      (select bool_and(extract(year from d) = annee) from unnest(jours_feries_fr(annee)) d),
      format('%s : aucun férié ne déborde sur une autre année', annee));
  end loop;
end $$;

-- `est_jour_ferie` ne se sert plus de `jours_feries_fr` : elle teste les huit
-- fériés fixes avant de calculer Pâques, et s'en dispense entièrement hors de la
-- fenêtre du 23 mars au 14 juin (migration 0017 § 1). C'est ce qui l'a rendue
-- 6,8 fois plus rapide — et c'est aussi une **seconde écriture de la liste**.
--
-- Une liste écrite deux fois n'est acceptable que vérifiée. Les deux formes sont
-- donc comparées jour par jour sur deux siècles : 73 414 dates, aucun désaccord
-- toléré. Un férié ajouté d'un côté et pas de l'autre fait rougir ce test à la
-- première seconde, et non le jour où un pompier compte un weekend de trop.
do $$
declare
  desaccords integer;
begin
  select count(*) into desaccords
    from generate_series(date '1900-01-01', date '2100-12-31', interval '1 day') g(d)
   where est_jour_ferie(d::date)
      <> (d::date = any (jours_feries_fr(extract(year from d)::integer)));
  perform tests_mat.egal(desaccords, 0,
    'est_jour_ferie et jours_feries_fr s''accordent sur 1900-2100');
end $$;

release savepoint s1;

-- ===========================================================================
-- 2. L'unité de weekend : la définition du client, pas une deuxième
-- ===========================================================================
\echo ''
\echo '--- 2. Unité de weekend : samedi+dimanche, férié en semaine, pas de doublon'
savepoint s2;

-- Mai 2027 est le mois d'épreuve : le 1er mai tombe un samedi, le 6 un jeudi,
-- le 8 un samedi, le 17 un lundi. Les quatre cas de la règle dans un seul mois.
do $$
begin
  -- Règle 1 : samedi et dimanche font une seule unité, désignée par le samedi.
  perform tests_mat.egal(unite_weekend(date '2027-05-15'), date '2027-05-15', 'samedi 15 mai');
  perform tests_mat.egal(unite_weekend(date '2027-05-16'), date '2027-05-15', 'dimanche 16 mai → samedi 15');

  -- Règle 2 : un férié du lundi au vendredi forme son unité.
  perform tests_mat.egal(unite_weekend(date '2027-05-06'), date '2027-05-06', 'jeudi 6 mai (Ascension)');
  perform tests_mat.egal(unite_weekend(date '2027-05-17'), date '2027-05-17', 'lundi 17 mai (Pentecôte)');

  -- Règle 3 : un férié le samedi ou le dimanche ne double pas l'unité.
  perform tests_mat.egal(unite_weekend(date '2027-05-01'), date '2027-05-01', 'samedi 1er mai (férié) = son weekend');
  perform tests_mat.egal(unite_weekend(date '2027-05-02'), date '2027-05-01', 'dimanche 2 mai → samedi 1er');
  perform tests_mat.egal(unite_weekend(date '2027-05-08'), date '2027-05-08', 'samedi 8 mai (férié) = son weekend');
  perform tests_mat.egal(unite_weekend(date '2027-05-09'), date '2027-05-08', 'dimanche 9 mai → samedi 8');

  -- Un jour ordinaire n'appartient à aucune unité.
  perform tests_mat.egal(unite_weekend(date '2027-05-12'), null::date, 'mercredi 12 mai');

  -- Le dimanche 1er août 2027 se rattache au samedi 31 juillet : l'unité
  -- traverse le mois, et c'est ce qui la rend unique (`uniteWeekend`, ticket 013).
  perform tests_mat.egal(unite_weekend(date '2027-08-01'), date '2027-07-31', 'dimanche 1er août → samedi 31 juillet');

  -- Le compte du mois : 1er, 6, 8, 15, 17, 22, 29 mai = sept unités. Quatre
  -- fériés dans le mois et pourtant sept unités, pas neuf : les 1er et 8 mai
  -- sont des samedis.
  perform tests_mat.egal(
    (select count(distinct unite_weekend(d::date))::int
       from generate_series(date '2027-05-01', date '2027-05-31', interval '1 day') d),
    7, 'unités de weekend de mai 2027');
end $$;

release savepoint s2;

-- ===========================================================================
-- Fixtures des sections 3 à 5
-- ===========================================================================
-- Deux casernes créées ici, sur 2027 :
--   M « CIS Matrice »  : 1 admin, 3 membres actifs, 1 membre désactivé ;
--   V « CIS Voisine »  : 1 admin, et le membre M1 qui sert aussi là-bas.
--
-- M1 sert dans les deux centres (docs/PRD.md § 6.1) : ses astreintes chez V ne
-- doivent jamais peser sur son quota chez M.

insert into stations (id, name, slug, timezone) values
  ('11111111-0000-4000-8000-000000000001', 'CIS Matrice', 'cis-matrice', 'Europe/Paris'),
  ('22222222-0000-4000-8000-000000000001', 'CIS Voisine', 'cis-voisine', 'Europe/Paris');

insert into auth.users (
  instance_id, id, aud, role, email, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new, email_change_token_current
)
select
  '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated',
  u.email, now(), '{"provider": "email", "providers": ["email"]}'::jsonb,
  jsonb_build_object('first_name', u.first_name, 'last_name', u.last_name),
  now(), now(), '', '', '', '', ''
from (values
  ('11111111-0000-4000-8000-000000000100'::uuid, 'admin@matrice.test',   'Hélène', 'Aubert'),
  ('11111111-0000-4000-8000-000000000101'::uuid, 'membre1@matrice.test', 'Bruno',  'Belin'),
  ('11111111-0000-4000-8000-000000000102'::uuid, 'membre2@matrice.test', 'Nadia',  'Cortes'),
  ('11111111-0000-4000-8000-000000000103'::uuid, 'membre3@matrice.test', 'Yann',   'Delaunay'),
  ('11111111-0000-4000-8000-000000000104'::uuid, 'ancien@matrice.test',  'Paul',   'Ermont'),
  ('22222222-0000-4000-8000-000000000100'::uuid, 'admin@voisine.test',   'Karim',  'Zerbi')
) as u(id, email, first_name, last_name);

insert into memberships (station_id, user_id, role, status, display_name) values
  ('11111111-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000100', 'admin',  'active',   'Hélène A.'),
  ('11111111-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000101', 'member', 'active',   'Bruno B.'),
  ('11111111-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000102', 'member', 'active',   'Nadia C.'),
  ('11111111-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000103', 'member', 'active',   null),
  ('11111111-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000104', 'member', 'disabled', 'Paul E.'),
  ('22222222-0000-4000-8000-000000000001', '22222222-0000-4000-8000-000000000100', 'admin',  'active',   'Karim Z.'),
  ('22222222-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000101', 'member', 'active',   'Bruno B.');

-- Périodes. Janvier 2027 sert à vérifier que l'historique s'arrête à trois mois ;
-- février 2028 (29 jours) et avril 2027 (30 jours) à vérifier la longueur des
-- chaînes de la matrice.
insert into periods (id, station_id, year, month, status, deadline_at) values
  ('11111111-0000-4000-8000-000000000201', '11111111-0000-4000-8000-000000000001', 2027,  1, 'locked', '2026-12-15 23:59:59+01'),
  ('11111111-0000-4000-8000-000000000204', '11111111-0000-4000-8000-000000000001', 2027,  4, 'locked', '2027-03-15 23:59:59+01'),
  ('11111111-0000-4000-8000-000000000205', '11111111-0000-4000-8000-000000000001', 2027,  5, 'open',   '2027-04-15 23:59:59+02'),
  ('11111111-0000-4000-8000-000000000206', '11111111-0000-4000-8000-000000000001', 2027,  6, 'open',   '2027-05-15 23:59:59+02'),
  ('11111111-0000-4000-8000-000000000228', '11111111-0000-4000-8000-000000000001', 2028,  2, 'open',   '2028-01-15 23:59:59+01'),
  ('22222222-0000-4000-8000-000000000205', '22222222-0000-4000-8000-000000000001', 2027,  5, 'open',   '2027-04-15 23:59:59+02');

-- Disponibilités de mai 2027 pour M1 : un motif choisi pour être lisible dans
-- la chaîne rendue. Jour : disponible les 1, 2 et 3, absent le 5, rien ailleurs.
-- Nuit : absent le 1er, disponible le 31.
insert into availabilities (station_id, user_id, date, slot, status, set_by) values
  ('11111111-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000101', '2027-05-01', 'day',   'available', '11111111-0000-4000-8000-000000000101'),
  ('11111111-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000101', '2027-05-02', 'day',   'available', '11111111-0000-4000-8000-000000000101'),
  ('11111111-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000101', '2027-05-03', 'day',   'available', '11111111-0000-4000-8000-000000000101'),
  ('11111111-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000101', '2027-05-05', 'day',   'absent',    '11111111-0000-4000-8000-000000000101'),
  ('11111111-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000101', '2027-05-01', 'night', 'absent',    '11111111-0000-4000-8000-000000000101'),
  ('11111111-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000101', '2027-05-31', 'night', 'available', '11111111-0000-4000-8000-000000000101'),
  -- Un mois voisin et une caserne voisine, pour vérifier qu'ils ne débordent
  -- pas dans la grille de mai chez M.
  ('11111111-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000101', '2027-06-01', 'day',   'available', '11111111-0000-4000-8000-000000000101'),
  ('22222222-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000101', '2027-05-10', 'day',   'available', '11111111-0000-4000-8000-000000000101'),
  -- Le membre désactivé a saisi de son vivant : sa ligne ne doit pas reparaître.
  ('11111111-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000104', '2027-05-04', 'day',   'available', '11111111-0000-4000-8000-000000000104'),
  -- Nadia n'a rien saisi ; l'admin a saisi **pour elle**. `set_by` diffère du
  -- titulaire : la matrice doit le dire en minuscules, et cette marque doit
  -- survivre au rechargement — sinon elle ne vit que dans la session qui a fait
  -- la saisie, et l'admin suivant ne voit plus qui a écrit quoi.
  ('11111111-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000102', '2027-05-02', 'day',   'available', '11111111-0000-4000-8000-000000000100'),
  ('11111111-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000102', '2027-05-04', 'night', 'absent',    '11111111-0000-4000-8000-000000000100'),
  -- Et une ligne ancienne, d'avant le déclencheur `availabilities_trace_auteur`
  -- (0012) : `set_by` est nul. Elle compte comme saisie par le membre — le cas
  -- le plus probable et le moins alarmant des deux.
  ('11111111-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000102', '2027-05-06', 'day',   'available', null);

-- Préférences du mois : M1 plafonné et bavard, M3 plafonné et muet, M2 sans rien.
insert into availability_preferences (station_id, user_id, period_id, max_shifts, max_weekends, comment) values
  ('11111111-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000101',
   '11111111-0000-4000-8000-000000000205', 8, 2, 'Pas de nuit la semaine du 10.'),
  ('11111111-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000103',
   '11111111-0000-4000-8000-000000000205', 5, null, null);

-- Plannings, créneaux et attributions.
insert into schedules (id, station_id, period_id, status, created_by) values
  ('11111111-0000-4000-8000-000000000301', '11111111-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000205', 'draft', '11111111-0000-4000-8000-000000000100'),
  ('11111111-0000-4000-8000-000000000304', '11111111-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000204', 'validated', '11111111-0000-4000-8000-000000000100'),
  ('11111111-0000-4000-8000-000000000331', '11111111-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000201', 'archived', '11111111-0000-4000-8000-000000000100'),
  ('22222222-0000-4000-8000-000000000301', '22222222-0000-4000-8000-000000000001', '22222222-0000-4000-8000-000000000205', 'validated', '22222222-0000-4000-8000-000000000100');

insert into shifts (id, station_id, schedule_id, date, slot)
select
  ('11111111-0000-4000-8000-0000004' || lpad(row_number() over (order by s.date, s.slot)::text, 5, '0'))::uuid,
  '11111111-0000-4000-8000-000000000001', s.schedule_id, s.date, s.slot
from (values
  -- Mai 2027, planning en cours : le weekend du 1er-2 mai en entier,
  -- l'Ascension du 6, le samedi férié du 8, et un mardi ordinaire.
  ('11111111-0000-4000-8000-000000000301'::uuid, date '2027-05-01', 'day'::slot_type),
  ('11111111-0000-4000-8000-000000000301'::uuid, date '2027-05-01', 'night'::slot_type),
  ('11111111-0000-4000-8000-000000000301'::uuid, date '2027-05-02', 'day'::slot_type),
  ('11111111-0000-4000-8000-000000000301'::uuid, date '2027-05-02', 'night'::slot_type),
  ('11111111-0000-4000-8000-000000000301'::uuid, date '2027-05-06', 'day'::slot_type),
  ('11111111-0000-4000-8000-000000000301'::uuid, date '2027-05-08', 'day'::slot_type),
  ('11111111-0000-4000-8000-000000000301'::uuid, date '2027-05-11', 'day'::slot_type),
  -- Avril 2027 : dans la fenêtre des trois mois précédents.
  ('11111111-0000-4000-8000-000000000304'::uuid, date '2027-04-03', 'day'::slot_type),
  ('11111111-0000-4000-8000-000000000304'::uuid, date '2027-04-04', 'day'::slot_type),
  ('11111111-0000-4000-8000-000000000304'::uuid, date '2027-04-20', 'day'::slot_type),
  -- Janvier 2027 : hors fenêtre.
  ('11111111-0000-4000-8000-000000000331'::uuid, date '2027-01-12', 'day'::slot_type)
) as s(schedule_id, date, slot);

insert into shifts (id, station_id, schedule_id, date, slot) values
  ('22222222-0000-4000-8000-000000040001', '22222222-0000-4000-8000-000000000001', '22222222-0000-4000-8000-000000000301', '2027-05-13', 'day'),
  ('22222222-0000-4000-8000-000000040002', '22222222-0000-4000-8000-000000000001', '22222222-0000-4000-8000-000000000301', '2027-05-14', 'day');

-- Attributions de M1. Chez M, mai 2027 :
--   acceptées   1er jour, 1er nuit, 2 jour, 2 nuit  → une seule unité (1er mai)
--   acceptée    6 mai (Ascension, jeudi)            → une unité
--   proposée    8 mai (samedi férié)                → une unité
--   refusée     11 mai                              → ne compte pas
-- soit 6 astreintes et 3 unités de weekend.
insert into assignments (station_id, shift_id, user_id, status, created_by, proposed_at, responded_at)
select
  '11111111-0000-4000-8000-000000000001', sh.id,
  '11111111-0000-4000-8000-000000000101', a.statut::assignment_status,
  '11111111-0000-4000-8000-000000000100', now(),
  case when a.statut in ('accepted', 'declined') then now() end
from (values
  (date '2027-05-01', 'day',   'accepted'),
  (date '2027-05-01', 'night', 'accepted'),
  (date '2027-05-02', 'day',   'accepted'),
  (date '2027-05-02', 'night', 'accepted'),
  (date '2027-05-06', 'day',   'accepted'),
  (date '2027-05-08', 'day',   'proposed'),
  (date '2027-05-11', 'day',   'declined'),
  -- Historique : avril 2027, deux acceptées et une proposée (qui ne compte pas).
  (date '2027-04-03', 'day',   'accepted'),
  (date '2027-04-04', 'day',   'accepted'),
  (date '2027-04-20', 'day',   'proposed'),
  -- Janvier 2027 : acceptée mais hors des trois mois précédant mai.
  (date '2027-01-12', 'day',   'accepted')
) as a(jour, creneau, statut)
join shifts sh
  on sh.station_id = '11111111-0000-4000-8000-000000000001'
 and sh.date = a.jour
 and sh.slot = a.creneau::slot_type;

-- Chez V, le même mois : deux astreintes acceptées qui ne regardent pas M.
insert into assignments (station_id, shift_id, user_id, status, created_by, proposed_at, responded_at)
select
  '22222222-0000-4000-8000-000000000001', sh.id,
  '11111111-0000-4000-8000-000000000101', 'accepted',
  '22222222-0000-4000-8000-000000000100', now(), now()
from shifts sh
where sh.station_id = '22222222-0000-4000-8000-000000000001';

-- ===========================================================================
-- 3. La forme de la matrice
-- ===========================================================================
\echo ''
\echo '--- 3. availability_matrix : une ligne par membre actif, le mois en deux chaînes'
savepoint s3;

set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
declare
  ligne record;
  nb    integer;
begin
  select count(*) into nb
    from availability_matrix(
      '11111111-0000-4000-8000-000000000001',
      '11111111-0000-4000-8000-000000000205');
  -- L'admin, les trois membres actifs. Pas le membre désactivé, même s'il a saisi.
  perform tests_mat.egal(nb, 4, 'lignes de la matrice (membres actifs, admin compris)');

  perform tests_mat.check(
    not exists (
      select 1 from availability_matrix(
        '11111111-0000-4000-8000-000000000001',
        '11111111-0000-4000-8000-000000000205')
      where user_id = '11111111-0000-4000-8000-000000000104'),
    'le membre désactivé n''a pas de ligne');

  select * into ligne
    from availability_matrix(
      '11111111-0000-4000-8000-000000000001',
      '11111111-0000-4000-8000-000000000205')
   where user_id = '11111111-0000-4000-8000-000000000101';

  -- Longueur : un caractère par jour du mois, mai en compte 31.
  perform tests_mat.egal(length(ligne.day_slots),   31, 'longueur de day_slots (mai)');
  perform tests_mat.egal(length(ligne.night_slots), 31, 'longueur de night_slots (mai)');

  -- Alphabet et positions. Jour : D D D . A puis 26 points.
  perform tests_mat.egal(ligne.day_slots,
    'DDD.A' || repeat('.', 26), 'grille de jour de Bruno B.');
  -- Nuit : A, 29 points, D — la disponibilité du 31 est bien en dernière position.
  perform tests_mat.egal(ligne.night_slots,
    'A' || repeat('.', 29) || 'D', 'grille de nuit de Bruno B.');

  -- Rien d'autre que « . D A d a » ne sort de la fonction.
  perform tests_mat.check(
    (select bool_and(day_slots ~ '^[.DAda]+$' and night_slots ~ '^[.DAda]+$')
       from availability_matrix(
         '11111111-0000-4000-8000-000000000001',
         '11111111-0000-4000-8000-000000000205')),
    'alphabet limité à « . D A d a »');

  -- Saisie par un administrateur pour un membre : minuscules. Nadia n'a rien
  -- écrit elle-même ; sa grille porte « d » le 2 (l'admin l'a dite disponible),
  -- « a » le 4 en nuit (l'admin l'a dite absente), et « D » le 6 — ligne sans
  -- `set_by`, donc attribuée au membre.
  perform tests_mat.egal(
    (select day_slots from availability_matrix(
       '11111111-0000-4000-8000-000000000001',
       '11111111-0000-4000-8000-000000000205')
      where user_id = '11111111-0000-4000-8000-000000000102'),
    '.d...D' || repeat('.', 25), 'grille de jour de Nadia C. (saisie admin)');
  perform tests_mat.egal(
    (select night_slots from availability_matrix(
       '11111111-0000-4000-8000-000000000001',
       '11111111-0000-4000-8000-000000000205')
      where user_id = '11111111-0000-4000-8000-000000000102'),
    '...a' || repeat('.', 27), 'grille de nuit de Nadia C. (saisie admin)');

  -- La casse est **la seule** différence : qui ignore la casse retrouve les
  -- trois états du schéma (docs/SCHEMA.md § 2.6). C'est le contrat donné à
  -- l'application, et il se vérifie.
  perform tests_mat.check(
    (select bool_and(upper(day_slots) ~ '^[.DA]+$' and upper(night_slots) ~ '^[.DA]+$')
       from availability_matrix(
         '11111111-0000-4000-8000-000000000001',
         '11111111-0000-4000-8000-000000000205')),
    'en ignorant la casse, trois états et pas un de plus');

  -- Un membre qui n'a rien saisi : deux chaînes pleines de points, jamais NULL.
  -- C'est le sens de « absence de ligne = non saisi » (docs/SCHEMA.md § 2.6).
  perform tests_mat.egal(
    (select day_slots from availability_matrix(
       '11111111-0000-4000-8000-000000000001',
       '11111111-0000-4000-8000-000000000205')
      where user_id = '11111111-0000-4000-8000-000000000103'),
    repeat('.', 31), 'membre sans aucune saisie : 31 points');

  -- Le commentaire du mois, lu par l'admin (critère du ticket 016).
  perform tests_mat.egal(ligne.comment, 'Pas de nuit la semaine du 10.',
    'commentaire du mois de Bruno B.');
  perform tests_mat.egal(
    (select comment from availability_matrix(
       '11111111-0000-4000-8000-000000000001',
       '11111111-0000-4000-8000-000000000205')
      where user_id = '11111111-0000-4000-8000-000000000102'),
    null::text, 'membre sans préférences : commentaire NULL');

  -- Le nom affiché retombe sur prénom + nom quand la caserne n'a pas de surnom.
  perform tests_mat.egal(
    (select display_name from availability_matrix(
       '11111111-0000-4000-8000-000000000001',
       '11111111-0000-4000-8000-000000000205')
      where user_id = '11111111-0000-4000-8000-000000000103'),
    'Yann Delaunay', 'display_name absent : prénom + nom');
end $$;

-- La longueur suit le mois : 30 jours en avril, 29 en février 2028 (bissextile).
do $$
begin
  perform tests_mat.egal(
    (select distinct length(day_slots) from availability_matrix(
       '11111111-0000-4000-8000-000000000001',
       '11111111-0000-4000-8000-000000000204')),
    30, 'longueur de la grille en avril 2027');
  perform tests_mat.egal(
    (select distinct length(night_slots) from availability_matrix(
       '11111111-0000-4000-8000-000000000001',
       '11111111-0000-4000-8000-000000000228')),
    29, 'longueur de la grille en février 2028 (bissextile)');
end $$;

-- Ni le mois voisin ni la caserne voisine ne débordent : la saisie du 1er juin
-- et celle faite chez V n'apparaissent pas dans la grille de mai chez M.
do $$
begin
  perform tests_mat.egal(
    (select day_slots from availability_matrix(
       '11111111-0000-4000-8000-000000000001',
       '11111111-0000-4000-8000-000000000206')
      where user_id = '11111111-0000-4000-8000-000000000101'),
    'D' || repeat('.', 29), 'juin 2027 : seule la saisie du 1er juin');
end $$;

reset role;
release savepoint s3;

-- ===========================================================================
-- 4. v_member_load : la charge, et les quotas de l'écran
-- ===========================================================================
\echo ''
\echo '--- 4. v_member_load : astreintes, unités de weekend, restes, historique'
savepoint s4;

set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
declare
  charge v_member_load;
begin
  select * into charge from v_member_load
   where station_id = '11111111-0000-4000-8000-000000000001'
     and period_id  = '11111111-0000-4000-8000-000000000205'
     and user_id    = '11111111-0000-4000-8000-000000000101';

  -- Cinq acceptées + une proposée. La refusée du 11 mai ne compte pas : elle
  -- n'engage plus personne (docs/SCHEMA.md § 2.10).
  perform tests_mat.egal(charge.shifts_count, 6, 'astreintes proposées ou acceptées');

  -- Quatre créneaux du weekend du 1er-2 mai = une unité, l'Ascension du 6 = une,
  -- le samedi férié du 8 = une. Trois, et non six.
  perform tests_mat.egal(charge.weekend_units, 3, 'unités de weekend couvertes');

  perform tests_mat.egal(charge.max_shifts,   8, 'plafond d''astreintes déclaré');
  perform tests_mat.egal(charge.max_weekends, 2, 'plafond de weekends déclaré');
  perform tests_mat.egal(charge.shifts_left,  2, 'astreintes restantes');
  -- Reste négatif : le plafond de weekends est dépassé d'une unité. Le PRD § 5.3
  -- autorise l'admin à passer outre avec avertissement — encore faut-il que le
  -- chiffre le lui dise.
  perform tests_mat.egal(charge.weekends_left, -1, 'weekends restants (dépassement)');

  -- Historique : les deux acceptées d'avril. Ni la proposée d'avril, ni
  -- l'acceptée de janvier, qui est à quatre mois de mai.
  perform tests_mat.egal(charge.accepted_previous, 2,
    'astreintes acceptées sur les trois mois précédents');
end $$;

do $$
declare
  charge v_member_load;
begin
  -- Un membre sans préférences : plafonds NULL, et restes NULL. Un illimité
  -- n'a pas de reste — rendre 0 ferait griser un pompier qui n'a rien demandé.
  select * into charge from v_member_load
   where station_id = '11111111-0000-4000-8000-000000000001'
     and period_id  = '11111111-0000-4000-8000-000000000205'
     and user_id    = '11111111-0000-4000-8000-000000000102';
  perform tests_mat.egal(charge.shifts_count,      0, 'membre sans astreinte : 0');
  perform tests_mat.egal(charge.weekend_units,     0, 'membre sans astreinte : 0 weekend');
  perform tests_mat.egal(charge.max_shifts,        null::integer, 'plafond illimité');
  perform tests_mat.egal(charge.shifts_left,       null::integer, 'reste d''un illimité : NULL');
  perform tests_mat.egal(charge.weekends_left,     null::integer, 'reste de weekends illimités : NULL');
  perform tests_mat.egal(charge.accepted_previous, 0, 'historique vide');

  -- Plafond d'astreintes déclaré, plafond de weekends laissé libre : les deux
  -- colonnes sont indépendantes.
  select * into charge from v_member_load
   where station_id = '11111111-0000-4000-8000-000000000001'
     and period_id  = '11111111-0000-4000-8000-000000000205'
     and user_id    = '11111111-0000-4000-8000-000000000103';
  perform tests_mat.egal(charge.shifts_left,   5, 'reste d''astreintes sans charge');
  perform tests_mat.egal(charge.weekends_left, null::integer, 'weekends illimités malgré max_shifts');
end $$;

do $$
begin
  -- Une ligne par membre actif et par période, toujours : le membre désactivé
  -- n'y est pas, les trois membres actifs et l'admin y sont.
  perform tests_mat.egal(
    (select count(*)::int from v_member_load
      where station_id = '11111111-0000-4000-8000-000000000001'
        and period_id = '11111111-0000-4000-8000-000000000205'),
    4, 'lignes de v_member_load pour mai 2027');
  perform tests_mat.check(
    not exists (select 1 from v_member_load
                 where user_id = '11111111-0000-4000-8000-000000000104'),
    'le membre désactivé n''a pas de charge');
end $$;

-- Les quotas de la matrice **sont** ceux de la vue : c'est le critère
-- d'acceptation du ticket. Comparaison ligne à ligne, pas à l'œil.
do $$
declare
  ecarts integer;
begin
  select count(*) into ecarts
  from availability_matrix(
         '11111111-0000-4000-8000-000000000001',
         '11111111-0000-4000-8000-000000000205') mx
  join v_member_load ml
    on ml.station_id = '11111111-0000-4000-8000-000000000001'
   and ml.period_id  = '11111111-0000-4000-8000-000000000205'
   and ml.user_id    = mx.user_id
  where (mx.max_shifts, mx.max_weekends, mx.shifts_count, mx.weekend_units,
         mx.shifts_left, mx.weekends_left, mx.accepted_previous)
     is distinct from
        (ml.max_shifts, ml.max_weekends, ml.shifts_count, ml.weekend_units,
         ml.shifts_left, ml.weekends_left, ml.accepted_previous);
  perform tests_mat.egal(ecarts, 0, 'la matrice et v_member_load donnent les mêmes quotas');
end $$;

reset role;

-- Cloisonnement : les deux astreintes de Bruno chez la caserne voisine ne
-- pèsent pas sur son quota chez M, et réciproquement.
set local role authenticated;
set local request.jwt.claims = '{"sub":"22222222-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
begin
  perform tests_mat.egal(
    (select shifts_count from v_member_load
      where station_id = '22222222-0000-4000-8000-000000000001'
        and period_id = '22222222-0000-4000-8000-000000000205'
        and user_id = '11111111-0000-4000-8000-000000000101'),
    2, 'chez la caserne voisine : ses deux astreintes à elle');
end $$;

reset role;
release savepoint s4;

-- ===========================================================================
-- 5. Les droits
-- ===========================================================================
\echo ''
\echo '--- 5. Droits : admin de sa caserne seulement, membre exclu, anon exclu'
savepoint s5;

-- Un membre n'obtient pas la matrice, même la sienne : l'écran est celui du chef
-- de centre. Lui rendre une matrice d'une ligne laisserait croire le contraire.
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-0000-4000-8000-000000000101","role":"authenticated"}';

do $$
begin
  perform tests_mat.refuse(
    $sql$select * from availability_matrix(
      '11111111-0000-4000-8000-000000000001',
      '11111111-0000-4000-8000-000000000205')$sql$,
    'forbidden', 'un membre n''ouvre pas la matrice de sa caserne');

  -- Ce qu'il lit dans v_member_load n'est rien de plus qu'aujourd'hui : il voit
  -- les lignes de ses collègues (il lit déjà `memberships`), mais leurs plafonds
  -- restent NULL et leurs charges à zéro. Yann a pourtant un max_shifts de 5.
  perform tests_mat.egal(
    (select max_shifts from v_member_load
      where station_id = '11111111-0000-4000-8000-000000000001'
        and period_id = '11111111-0000-4000-8000-000000000205'
        and user_id = '11111111-0000-4000-8000-000000000103'),
    null::integer, 'un membre ne lit pas le plafond d''un collègue');

  -- Et il ne voit rien du tout de la caserne dont il n'est pas membre.
  perform tests_mat.egal(
    (select count(*)::int from v_member_load
      where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'),
    0, 'un membre de M ne voit aucune ligne de la caserne A du seed');
end $$;

reset role;

-- Un admin ne sort pas de sa caserne.
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
begin
  perform tests_mat.refuse(
    $sql$select * from availability_matrix(
      '22222222-0000-4000-8000-000000000001',
      '22222222-0000-4000-8000-000000000205')$sql$,
    'forbidden', 'l''admin de M n''ouvre pas la matrice de V');

  -- Même en présentant la bonne caserne et une période qui ne lui appartient
  -- pas : la période est contrôlée, pas seulement la caserne.
  perform tests_mat.refuse(
    $sql$select * from availability_matrix(
      '11111111-0000-4000-8000-000000000001',
      '22222222-0000-4000-8000-000000000205')$sql$,
    'period_not_found', 'une période d''une autre caserne est refusée');

  perform tests_mat.egal(
    (select count(*)::int from v_member_load
      where station_id <> '11111111-0000-4000-8000-000000000001'),
    0, 'l''admin de M ne lit aucune charge d''une autre caserne');
end $$;

reset role;

-- La caserne A du seed contre la caserne B : le test de fuite habituel, sur les
-- deux objets de cette migration.
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
declare
  periode_a uuid;
  periode_b uuid;
begin
  select id into periode_a from periods
   where station_id = 'aaaaaaaa-0000-4000-8000-000000000001' order by year, month limit 1;
  select id into periode_b from periods
   where station_id = 'bbbbbbbb-0000-4000-8000-000000000001' order by year, month limit 1;

  perform tests_mat.check(
    (select count(*) from availability_matrix('aaaaaaaa-0000-4000-8000-000000000001', periode_a)) = 9,
    'l''admin de A lit les neuf lignes de A');

  perform tests_mat.refuse(
    format($sql$select * from availability_matrix('bbbbbbbb-0000-4000-8000-000000000001', %L)$sql$, periode_b),
    'forbidden', 'l''admin de A n''ouvre pas la matrice de B');

  perform tests_mat.egal(
    (select count(*)::int from v_member_load
      where station_id = 'bbbbbbbb-0000-4000-8000-000000000001'),
    0, 'l''admin de A ne lit aucune charge de B');
end $$;

reset role;

-- `anon` n'appelle pas la fonction et ne lit pas la vue.
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

do $$
begin
  perform tests_mat.refuse(
    $sql$select * from availability_matrix(
      '11111111-0000-4000-8000-000000000001',
      '11111111-0000-4000-8000-000000000205')$sql$,
    'permission denied for function availability_matrix',
    'anon n''appelle pas availability_matrix');
  -- Pas « zéro ligne » mais « pas le droit de regarder » : le `revoke all …
  -- from anon` de la migration tranche avant que la RLS n'ait à filtrer.
  perform tests_mat.refuse(
    $sql$select count(*) from v_member_load$sql$,
    'permission denied for view v_member_load',
    'anon ne lit pas v_member_load');
end $$;

reset role;
release savepoint s5;

-- ===========================================================================
-- 6. Performance : la caserne de soixante
-- ===========================================================================
-- `PRODUCT.md` vise soixante membres et le ticket 016 deux secondes pour
-- l'écran entier, réseau et peinture comprises. Ce qui se mesure ici est la part
-- de la base : si elle n'est pas d'un ordre de grandeur en dessous du budget,
-- le reste n'a aucune chance.
--
-- Le jeu est le pire cas raisonnable : soixante membres, octobre 2027 (31
-- jours), **toutes** les cellules saisies — 3 720 lignes de disponibilités, là
-- où un mois réel en compte plutôt la moitié —, plus un mois d'attributions et
-- trois mois d'historique.
\echo ''
\echo '--- 6. Performance : 60 membres × 31 jours × 2 créneaux'
savepoint s6;

insert into stations (id, name, slug, timezone) values
  ('33333333-0000-4000-8000-000000000001', 'CIS Soixante', 'cis-soixante', 'Europe/Paris');

insert into auth.users (
  instance_id, id, aud, role, email, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new, email_change_token_current
)
select
  '00000000-0000-0000-0000-000000000000',
  ('33333333-0000-4000-8000-0000000' || lpad(n::text, 5, '0'))::uuid,
  'authenticated', 'authenticated',
  'pompier' || n || '@soixante.test', now(),
  '{"provider": "email", "providers": ["email"]}'::jsonb,
  jsonb_build_object('first_name', 'Pompier', 'last_name', 'Numéro ' || lpad(n::text, 2, '0')),
  now(), now(), '', '', '', '', ''
from generate_series(1, 60) n;

insert into memberships (station_id, user_id, role, status, display_name)
select
  '33333333-0000-4000-8000-000000000001',
  ('33333333-0000-4000-8000-0000000' || lpad(n::text, 5, '0'))::uuid,
  (case when n = 1 then 'admin' else 'member' end)::membership_role,
  'active',
  'Pompier ' || lpad(n::text, 2, '0')
from generate_series(1, 60) n;

insert into periods (id, station_id, year, month, status, deadline_at) values
  ('33333333-0000-4000-8000-000000000207', '33333333-0000-4000-8000-000000000001', 2027,  7, 'locked', '2027-06-15 23:59:59+02'),
  ('33333333-0000-4000-8000-000000000208', '33333333-0000-4000-8000-000000000001', 2027,  8, 'locked', '2027-07-15 23:59:59+02'),
  ('33333333-0000-4000-8000-000000000209', '33333333-0000-4000-8000-000000000001', 2027,  9, 'locked', '2027-08-15 23:59:59+02'),
  ('33333333-0000-4000-8000-000000000210', '33333333-0000-4000-8000-000000000001', 2027, 10, 'open',   '2027-09-15 23:59:59+02');

-- Toutes les cellules du mois pour les soixante : 60 × 31 × 2 = 3 720 lignes.
insert into availabilities (station_id, user_id, date, slot, status, set_by)
select
  '33333333-0000-4000-8000-000000000001',
  m.user_id,
  d::date,
  s.slot,
  case when (extract(day from d)::int + n.rang) % 5 = 0 then 'absent' else 'available' end::availability_status,
  m.user_id
from memberships m
join lateral (select row_number() over (order by m.user_id) as rang) n on true
cross join generate_series(date '2027-10-01', date '2027-10-31', interval '1 day') d
cross join (values ('day'::slot_type), ('night'::slot_type)) s(slot)
where m.station_id = '33333333-0000-4000-8000-000000000001';

insert into availability_preferences (station_id, user_id, period_id, max_shifts, max_weekends, comment)
select
  '33333333-0000-4000-8000-000000000001', m.user_id,
  '33333333-0000-4000-8000-000000000210',
  6, 2,
  case when random() < 0.3 then 'Commentaire du mois.' end
from memberships m
where m.station_id = '33333333-0000-4000-8000-000000000001';

-- Un planning par mois, 62 créneaux chacun, et des attributions réparties sur
-- les soixante : ~6 astreintes par membre et par mois, 4 mois.
insert into schedules (id, station_id, period_id, status, created_by)
select
  ('33333333-0000-4000-8000-0000000003' || lpad(p.month::text, 2, '0'))::uuid,
  '33333333-0000-4000-8000-000000000001', p.id,
  case when p.month = 10 then 'draft' else 'validated' end::schedule_status,
  '33333333-0000-4000-8000-000000000001'
from periods p where p.station_id = '33333333-0000-4000-8000-000000000001';

insert into shifts (station_id, schedule_id, date, slot)
select
  '33333333-0000-4000-8000-000000000001', sc.id, d::date, s.slot
from schedules sc
join periods p on p.id = sc.period_id
cross join lateral generate_series(
  make_date(p.year, p.month, 1),
  (make_date(p.year, p.month, 1) + interval '1 month' - interval '1 day')::date,
  interval '1 day') d
cross join (values ('day'::slot_type), ('night'::slot_type)) s(slot)
where sc.station_id = '33333333-0000-4000-8000-000000000001';

insert into assignments (station_id, shift_id, user_id, status, created_by, proposed_at, responded_at)
select
  '33333333-0000-4000-8000-000000000001',
  sh.id,
  ('33333333-0000-4000-8000-0000000' || lpad((((extract(day from sh.date)::int * 2
      + case sh.slot when 'day' then 0 else 1 end + k) % 60) + 1)::text, 5, '0'))::uuid,
  case when sh.date >= date '2027-10-01' and k % 3 = 0 then 'proposed' else 'accepted' end::assignment_status,
  '33333333-0000-4000-8000-000000000001',
  now(), now()
from shifts sh
cross join generate_series(0, 5) k
where sh.station_id = '33333333-0000-4000-8000-000000000001';

analyze availabilities;
analyze assignments;
analyze shifts;
analyze memberships;
analyze availability_preferences;

-- La mesure se fait **sous le rôle de l'application**, pas sous celui du
-- propriétaire de la fonction, et c'est le point de tout ce bloc.
--
-- `availability_matrix` est `security definer` : appelée par `postgres`, elle
-- n'est pas la même chose qu'appelée par `authenticated`. Le piège est double.
--
--   1. Sous `postgres`, `auth.uid()` est nul, `is_admin()` répond faux, et la
--      fonction sort en trois millisecondes **par la porte du refus**. Chronomé-
--      trer ce chemin-là, c'est chronométrer une exception, pas une matrice. La
--      confusion a déjà été faite une fois en revue du ticket 016 ; elle ne doit
--      pas pouvoir se refaire sans que ce fichier le dise.
--   2. Une refonte qui abandonnerait `security definer` — une vue lue sous la
--      RLS de l'appelant, par exemple — rendrait exactement les mêmes lignes et
--      passerait tous les tests fonctionnels, en coûtant dix fois plus cher à
--      l'application et rien du tout au propriétaire.
--
-- D'où les deux mesures ci-dessous et, surtout, la comparaison des deux.
set local request.jwt.claims = '{"sub":"33333333-0000-4000-8000-000000000001","role":"authenticated"}';

-- Premier temps : le rôle propriétaire, avec les mêmes claims. C'est le
-- plancher — le coût du travail lui-même, RLS mise à part. Le résultat est
-- rangé dans un réglage de session pour être relu après le changement de rôle.
do $$
declare
  depart        timestamptz;
  duree_ms      double precision;
  proprietaire  double precision := 1e9;
begin
  for i in 1..5 loop
    depart := clock_timestamp();
    perform count(*) from availability_matrix(
      '33333333-0000-4000-8000-000000000001',
      '33333333-0000-4000-8000-000000000210');
    duree_ms := extract(epoch from (clock_timestamp() - depart)) * 1000;
    proprietaire := least(proprietaire, duree_ms);
  end loop;
  raise notice '  matrice 60 × 31 × 2 — rôle propriétaire : % ms', round(proprietaire::numeric, 1);
  perform set_config('tests_mat.proprietaire_ms', proprietaire::text, true);
end $$;

-- Second temps : `authenticated`, ce que fait vraiment l'application.
set local role authenticated;

do $$
declare
  depart        timestamptz;
  duree_ms      double precision;
  meilleure     double precision := 1e9;
  proprietaire  double precision := current_setting('tests_mat.proprietaire_ms')::double precision;
  lignes        integer;
  cellules      integer;
begin
  for i in 1..5 loop
    depart := clock_timestamp();
    select count(*), sum(length(day_slots) + length(night_slots))
      into lignes, cellules
      from availability_matrix(
        '33333333-0000-4000-8000-000000000001',
        '33333333-0000-4000-8000-000000000210');
    duree_ms := extract(epoch from (clock_timestamp() - depart)) * 1000;
    raise notice '  matrice 60 × 31 × 2 — authenticated, passage % : % ms', i, round(duree_ms::numeric, 1);
    meilleure := least(meilleure, duree_ms);
  end loop;

  perform tests_mat.egal(lignes, 60, 'lignes rendues');
  perform tests_mat.egal(cellules, 60 * 31 * 2, 'cellules rendues');

  -- Le seuil est large à dessein : il est là pour attraper une régression d'un
  -- ordre de grandeur (un index perdu, une jointure devenue corrélée, une RLS
  -- qui redescend dans la boucle), pas pour mesurer la machine de CI. Le chiffre
  -- réel est imprimé juste au-dessus.
  perform tests_mat.check(meilleure < 1000,
    format('matrice sous la seconde, rôle applicatif (meilleur passage : %s ms)',
           round(meilleure::numeric, 1)));

  -- Et le rapport entre les deux : le rôle de l'appelant ne doit rien changer au
  -- coût. Un facteur trois laisse passer le bruit d'une machine partagée et
  -- attrape le jour où la RLS revient se payer à chaque ligne.
  perform tests_mat.check(meilleure < 3 * greatest(proprietaire, 1),
    format('le rôle de l''appelant ne change pas le coût (%s ms contre %s ms)',
           round(meilleure::numeric, 1), round(proprietaire::numeric, 1)));
end $$;

-- `v_member_load` lue **directement** par un admin, c'est-à-dire par PostgREST,
-- coûte un ordre de grandeur de plus que la même vue lue depuis la matrice.
-- Ce n'est pas la vue qui est lente, c'est la RLS d'`assignments` et de `shifts` :
-- trois politiques permissives, deux `exists` vers `schedules`, et `is_admin()`
-- qui est `security definer` donc non inlinable — Postgres l'appelle une fois par
-- ligne examinée, soit ~30 000 fois pour soixante membres. La matrice, elle, est
-- `security definer` : elle lit la vue sous l'identité de son propriétaire et ne
-- paie ce tri qu'une fois, dans son propre `is_admin` d'entrée.
--
-- L'écran du ticket 016 n'emprunte donc pas ce chemin, et c'est à savoir pour les
-- tickets 017 et 018, qui voudront la charge des membres pour classer des
-- candidats : passer par une fonction `security definer` qui contrôle l'admin en
-- tête, comme ici, ou par la clé de service dans une Edge Function.
do $$
declare
  depart    timestamptz;
  duree_ms  double precision;
  lignes    integer;
  total     integer;
begin
  depart := clock_timestamp();
  -- Les colonnes calculées sont **consommées** : un simple `count(*)` laisserait
  -- le planificateur supprimer les jointures latérales, qui sont précisément ce
  -- que l'on mesure, et la vue paraîtrait gratuite.
  select count(*), sum(shifts_count + weekend_units + accepted_previous)
    into lignes, total
    from v_member_load
   where station_id = '33333333-0000-4000-8000-000000000001'
     and period_id = '33333333-0000-4000-8000-000000000210';
  duree_ms := extract(epoch from (clock_timestamp() - depart)) * 1000;
  raise notice '  v_member_load lue directement, 60 membres — % ms', round(duree_ms::numeric, 1);
  perform tests_mat.egal(lignes, 60, 'lignes de charge');

  -- Filet large : il attrape une régression d'un ordre de grandeur, il ne mesure
  -- pas la machine de CI. Le chiffre réel est imprimé juste au-dessus.
  perform tests_mat.check(duree_ms < 3000,
    format('charge des soixante lue directement (%s ms)', round(duree_ms::numeric, 1)));
end $$;

reset role;
release savepoint s6;

\echo ''
\echo '=== Matrice des disponibilités : tous les tests sont passés ==='

rollback;
