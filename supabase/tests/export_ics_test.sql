-- Tests du flux calendrier (migration 0029, ticket 028).
-- Lancement : scripts/test_rls.sh (ou psql -v ON_ERROR_STOP=1 -f ce fichier).
--
-- Ce qui est vérifié
-- ------------------
-- 1. Un jeton valide rend les astreintes **acceptées** de son porteur, et rien
--    d'autre : ni ses propositions en attente, ni les gardes d'un collègue, ni
--    quoi que ce soit d'une autre caserne.
-- 2. Un jeton inconnu, vide ou nul rend `unknown_token` — jamais une exception,
--    jamais un flux vide qu'on prendrait pour un abonnement qui marche.
-- 3. Régénérer invalide l'ancien jeton **sur-le-champ**.
-- 4. Une appartenance `disabled` retire les astreintes de cette caserne du flux.
-- 5. Le jeton n'est lisible par personne d'autre, pas même dans sa caserne, et
--    il ne s'écrit pas à la main.
-- 6. `ics_feed_events` n'est exécutable ni par `authenticated` ni par `anon` :
--    son paramètre est un porteur de droits.
-- 7. Le jeton n'entre pas dans l'export RGPD (`0027`), qui est un fichier qui
--    voyage.
--
-- Méthode identique à rls_test.sql : pas de pgTAP, une exception fait sortir psql
-- avec un code non nul. Tout le fichier tourne dans une transaction annulée.
--
-- Fixtures : le seed (caserne A = aaaaaaaa-…-001, membres …101 et …102 ;
-- caserne B = bbbbbbbb-…-001, membre …101) plus un planning publié et quatre
-- attributions, posés ici : le seed n'en crée aucun.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests;

create function tests.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

grant usage on schema tests to authenticated, anon, service_role;
grant execute on all functions in schema tests to authenticated, anon, service_role;

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
-- Caserne A, planning publié, trois créneaux :
--   - J+10 jour  : moi, accepté          → doit sortir
--   - J+10 nuit  : moi, proposé          → ne doit pas sortir
--   - J+11 jour  : un collègue, accepté  → ne doit jamais sortir
-- Caserne B, planning publié, un créneau :
--   - J+12 jour  : le membre 1 de la caserne B, accepté → son flux à lui
-- Et une astreinte acceptée il y a 200 jours, hors de la fenêtre du flux.
do $$
declare
  v_station_a uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
  v_station_b uuid := 'bbbbbbbb-0000-4000-8000-000000000001';
  v_moi       uuid := 'aaaaaaaa-0000-4000-8000-000000000101';
  v_collegue  uuid := 'aaaaaaaa-0000-4000-8000-000000000102';
  v_admin_a   uuid := 'aaaaaaaa-0000-4000-8000-000000000100';
  v_voisin    uuid := 'bbbbbbbb-0000-4000-8000-000000000101';
  v_admin_b   uuid := 'bbbbbbbb-0000-4000-8000-000000000100';
  v_period    uuid;
  v_schedule  uuid;
  v_shift     uuid;
begin
  select id into v_period from periods
   where station_id = v_station_a order by year, month limit 1;

  insert into schedules (station_id, period_id, status, created_by, published_at)
  values (v_station_a, v_period, 'published', v_admin_a, now())
  returning id into v_schedule;

  insert into shifts (station_id, schedule_id, date, slot, required_count)
  values (v_station_a, v_schedule, current_date + 10, 'day', 1)
  returning id into v_shift;
  insert into assignments (station_id, shift_id, user_id, status, created_by,
                           proposed_at, responded_at)
  values (v_station_a, v_shift, v_moi, 'accepted', v_admin_a, now(), now());

  insert into shifts (station_id, schedule_id, date, slot, required_count)
  values (v_station_a, v_schedule, current_date + 10, 'night', 1)
  returning id into v_shift;
  insert into assignments (station_id, shift_id, user_id, status, created_by, proposed_at)
  values (v_station_a, v_shift, v_moi, 'proposed', v_admin_a, now());

  insert into shifts (station_id, schedule_id, date, slot, required_count)
  values (v_station_a, v_schedule, current_date + 11, 'day', 1)
  returning id into v_shift;
  insert into assignments (station_id, shift_id, user_id, status, created_by,
                           proposed_at, responded_at)
  values (v_station_a, v_shift, v_collegue, 'accepted', v_admin_a, now(), now());

  insert into shifts (station_id, schedule_id, date, slot, required_count)
  values (v_station_a, v_schedule, current_date - 200, 'day', 1)
  returning id into v_shift;
  insert into assignments (station_id, shift_id, user_id, status, created_by,
                           proposed_at, responded_at)
  values (v_station_a, v_shift, v_moi, 'accepted', v_admin_a, now(), now());

  select id into v_period from periods
   where station_id = v_station_b order by year, month limit 1;

  insert into schedules (station_id, period_id, status, created_by, published_at)
  values (v_station_b, v_period, 'published', v_admin_b, now())
  returning id into v_schedule;

  insert into shifts (station_id, schedule_id, date, slot, required_count)
  values (v_station_b, v_schedule, current_date + 12, 'day', 1)
  returning id into v_shift;
  insert into assignments (station_id, shift_id, user_id, status, created_by,
                           proposed_at, responded_at)
  values (v_station_b, v_shift, v_voisin, 'accepted', v_admin_b, now(), now());
end $$;

\echo ''
\echo '=== 1. Un jeton valide rend les astreintes acceptées de son porteur ==='

savepoint s1;

do $$
declare
  v_moi      uuid := 'aaaaaaaa-0000-4000-8000-000000000101';
  v_token    text;
  v_flux     jsonb;
  v_evt      jsonb;
begin
  select ics_token into v_token from profiles where id = v_moi;
  perform tests.check(length(v_token) = 48,
    'le jeton fait 48 caractères hexadécimaux (24 octets tirés au sort)');
  perform tests.check(v_token ~ '^[0-9a-f]+$', 'et rien qui ait à être échappé dans une URL');

  v_flux := ics_feed_events(v_token);

  perform tests.check(v_flux ->> 'ok' = 'true', 'le flux répond');
  perform tests.check(v_flux ->> 'membre' = v_moi::text, 'et il désigne le bon membre');
  perform tests.check(jsonb_array_length(v_flux -> 'evenements') = 1,
    'un seul événement : l''astreinte acceptée à venir');

  v_evt := v_flux -> 'evenements' -> 0;
  perform tests.check(v_evt ->> 'date' = (current_date + 10)::text, 'la bonne date');
  perform tests.check(v_evt ->> 'creneau' = 'day', 'le bon créneau');
  perform tests.check(v_evt ->> 'caserne' = 'CIS Saint-Martin', 'la caserne est nommée');
  perform tests.check(v_evt ->> 'fuseau' = 'Europe/Paris', 'le fuseau de la caserne');
  perform tests.check(v_evt ->> 'debut_jour' = '07:00' and v_evt ->> 'fin_jour' = '19:00',
    'les heures viennent des paramètres de la caserne');

  -- **Le point de sécurité** : ce fichier voyage. Rien de personne d'autre.
  perform tests.check(v_flux::text not like '%Durand%' and v_flux::text not like '%Lefebvre%',
    'aucun nom de personne dans le flux, pas même le sien');
  perform tests.check(v_flux::text not like '%caserne-a.test%',
    'aucune adresse de courriel');
  perform tests.check(v_flux::text not like '%Val-de-Loue%',
    'rien de la caserne voisine');
end $$;

do $$
declare
  v_collegue uuid := 'aaaaaaaa-0000-4000-8000-000000000102';
  v_flux     jsonb;
begin
  -- Le collègue de la même caserne, avec **son** jeton : il voit sa garde à lui,
  -- jamais la mienne, alors que nous partageons le planning.
  v_flux := ics_feed_events((select ics_token from profiles where id = v_collegue));
  perform tests.check(jsonb_array_length(v_flux -> 'evenements') = 1,
    'le collègue voit une seule astreinte : la sienne');
  perform tests.check(v_flux -> 'evenements' -> 0 ->> 'date' = (current_date + 11)::text,
    'et c''est bien la sienne, pas la mienne');
end $$;

do $$
declare
  v_voisin uuid := 'bbbbbbbb-0000-4000-8000-000000000101';
  v_flux   jsonb;
begin
  v_flux := ics_feed_events((select ics_token from profiles where id = v_voisin));
  perform tests.check(v_flux ->> 'ok' = 'true', 'le membre de la caserne B a son flux');
  perform tests.check(v_flux::text like '%Val-de-Loue%', 'avec sa caserne à lui');
  perform tests.check(v_flux::text not like '%Saint-Martin%',
    'et rien de la caserne A');
end $$;

rollback to savepoint s1;

\echo ''
\echo '=== 2. Un jeton inconnu ne dit rien et ne lève rien ==='

savepoint s2;

do $$
begin
  perform tests.check(
    ics_feed_events('00000000000000000000000000000000000000000000dead') ->> 'code'
      = 'unknown_token',
    'un jeton inconnu : unknown_token');
  perform tests.check(ics_feed_events('') ->> 'code' = 'unknown_token',
    'un jeton vide : unknown_token');
  perform tests.check(ics_feed_events('   ') ->> 'code' = 'unknown_token',
    'un jeton blanc : unknown_token');
  perform tests.check(ics_feed_events(null) ->> 'code' = 'unknown_token',
    'un jeton nul : unknown_token');
  perform tests.check(ics_feed_events('dead') -> 'evenements' is null,
    'et aucun événement ne sort avec un refus');
end $$;

rollback to savepoint s2;

\echo ''
\echo '=== 3. Régénérer invalide l''ancien jeton sur-le-champ ==='

savepoint s3;

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

do $$
declare
  v_avant  text;
  v_apres  text;
begin
  v_avant := my_ics_token();
  perform tests.check(v_avant is not null, 'je lis mon propre jeton');

  v_apres := rotate_ics_token();
  perform tests.check(v_apres is not null and v_apres <> v_avant,
    'la régénération rend un jeton neuf');
  perform tests.check(my_ics_token() = v_apres,
    'et c''est celui que je relis ensuite');
end $$;

reset role;

do $$
declare
  v_moi   uuid := 'aaaaaaaa-0000-4000-8000-000000000101';
  v_apres text := (select ics_token from profiles where id = v_moi);
begin
  perform tests.check(ics_feed_events(v_apres) ->> 'ok' = 'true',
    'le nouveau jeton sert le flux');
end $$;

rollback to savepoint s3;

-- L'ancien jeton, relu après le rollback du savepoint, redevient l'actuel : la
-- preuve d'invalidation se fait donc dans une seule transaction, sans rollback.
savepoint s3b;

do $$
declare
  v_moi   uuid := 'aaaaaaaa-0000-4000-8000-000000000101';
  v_avant text := (select ics_token from profiles where id = v_moi);
  v_apres text;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}', true);
  v_apres := rotate_ics_token();

  perform tests.check(ics_feed_events(v_avant) ->> 'code' = 'unknown_token',
    'l''ancien jeton ne désigne plus personne, sans délai');
  perform tests.check(ics_feed_events(v_apres) ->> 'ok' = 'true',
    'le nouveau, lui, répond');
end $$;

do $$
begin
  -- Sans identité, rien ne tourne : `rotate_ics_token` ne prend aucun paramètre,
  -- et c'est ce qui l'empêche d'être une porte pour couper l'abonnement d'un autre.
  perform set_config('request.jwt.claims', '', true);
  perform tests.check(rotate_ics_token() is null,
    'sans session, la régénération ne fait rien');
  perform tests.check(my_ics_token() is null,
    'et il n''y a aucun jeton à lire');
end $$;

rollback to savepoint s3b;

\echo ''
\echo '=== 4. Un membre désactivé sort du flux ==='

savepoint s4;

do $$
declare
  v_moi   uuid := 'aaaaaaaa-0000-4000-8000-000000000101';
  v_token text := (select ics_token from profiles where id = v_moi);
begin
  perform tests.check(jsonb_array_length(ics_feed_events(v_token) -> 'evenements') = 1,
    'avant : une astreinte au flux');

  update memberships set status = 'disabled'
   where user_id = v_moi and station_id = 'aaaaaaaa-0000-4000-8000-000000000001';

  perform tests.check(ics_feed_events(v_token) ->> 'ok' = 'true',
    'après : le flux répond toujours — l''abonnement n''est pas cassé');
  perform tests.check(jsonb_array_length(ics_feed_events(v_token) -> 'evenements') = 0,
    'mais il est vide : les astreintes de cette caserne n''en sont plus');
end $$;

rollback to savepoint s4;

\echo ''
\echo '=== 5. Une caserne suspendue continue d''alimenter le flux ==='

savepoint s5;

do $$
declare
  v_station uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
  v_moi     uuid := 'aaaaaaaa-0000-4000-8000-000000000101';
  v_token   text := (select ics_token from profiles where id = v_moi);
begin
  update subscriptions set status = 'suspended', suspended_at = now()
   where station_id = v_station;

  perform tests.check(not station_writable(v_station),
    'la caserne est bien passée en lecture seule');
  perform tests.check(jsonb_array_length(ics_feed_events(v_token) -> 'evenements') = 1,
    'et l''astreinte est toujours au flux : « suspendu » veut dire lecture seule, '
    'pas gardes annulées (docs/PRD.md § 6.6)');
end $$;

rollback to savepoint s5;

\echo ''
\echo '=== 6. Le jeton n''est lisible ni écrivable par un client ==='

savepoint s6;

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000102","role":"authenticated"}';

do $$
begin
  -- Le collègue de la même caserne : la RLS lui ouvre ma ligne entière
  -- (`profiles_select_self_or_same_station`). Seul le grant de colonne l'arrête.
  begin
    perform ics_token from profiles
     where id = 'aaaaaaaa-0000-4000-8000-000000000101';
    raise exception 'ECHEC : un membre de la caserne a lu le jeton d''un autre';
  exception
    when insufficient_privilege then null;
    when raise_exception then
      if sqlerrm like 'ECHEC%' then raise; end if;
  end;
  perform tests.check(true, 'un collègue ne lit pas mon jeton d''abonnement');

  -- Ni le sien, d'ailleurs : la colonne passe par la fonction, pas par la table.
  begin
    perform ics_token from profiles where id = auth.uid();
    raise exception 'ECHEC : le jeton se lit directement dans la table';
  exception
    when insufficient_privilege then null;
    when raise_exception then
      if sqlerrm like 'ECHEC%' then raise; end if;
  end;
  perform tests.check(true, 'même pour soi, la lecture directe de la colonne est refusée');

  -- Et il ne se choisit pas : un jeton écrit à la main n'est plus un secret.
  begin
    update profiles set ics_token = 'jeton-choisi-par-le-client' where id = auth.uid();
    raise exception 'ECHEC : le jeton a pu être écrit par un client';
  exception
    when insufficient_privilege then null;
    when raise_exception then
      if sqlerrm like 'ECHEC%' then raise; end if;
  end;
  perform tests.check(true, 'le jeton ne s''écrit pas depuis un client');

  -- Ce qui doit continuer de marcher après le remaniement des grants :
  perform tests.check(
    (select count(*) from profiles where id = auth.uid()) = 1,
    'le profil reste lisible');
  update profiles set phone = '+33600000000' where id = auth.uid();
  perform tests.check(true, 'et modifiable comme avant');

  -- La fonction du flux, elle, n'est pas une API cliente : son paramètre est le
  -- secret de quelqu'un. Une porte entrouverte est une porte fermée.
  begin
    perform ics_feed_events('peu importe');
    raise exception 'ECHEC : un membre a pu appeler ics_feed_events';
  exception
    when insufficient_privilege then null;
    when raise_exception then
      if sqlerrm like 'ECHEC%' then raise; end if;
  end;
  perform tests.check(true, 'ics_feed_events est refusée à authenticated');
end $$;

reset role;

set local role anon;

do $$
begin
  begin
    perform ics_feed_events('peu importe');
    raise exception 'ECHEC : anon a pu appeler ics_feed_events';
  exception
    when insufficient_privilege then null;
    when raise_exception then
      if sqlerrm like 'ECHEC%' then raise; end if;
  end;
  perform tests.check(true, 'ics_feed_events est refusée à anon');

  begin
    perform my_ics_token();
    raise exception 'ECHEC : anon a pu appeler my_ics_token';
  exception
    when insufficient_privilege then null;
    when raise_exception then
      if sqlerrm like 'ECHEC%' then raise; end if;
  end;
  perform tests.check(true, 'my_ics_token est refusée à anon');
end $$;

reset role;

rollback to savepoint s6;

\echo ''
\echo '=== 7. Le jeton n''entre pas dans l''export RGPD ==='

savepoint s7;

do $$
declare
  v_moi    uuid := 'aaaaaaaa-0000-4000-8000-000000000101';
  v_token  text := (select ics_token from profiles where id = v_moi);
  v_export text := export_own_data(v_moi)::text;
begin
  -- L'export est un fichier qui voyage par courriel : y recopier un porteur de
  -- droits, c'est le compromettre. Même règle qu'`invitations.token` (`0027`).
  perform tests.check(position(v_token in v_export) = 0,
    'le jeton d''abonnement n''est pas dans l''export RGPD');
  perform tests.check(position('ics_token' in v_export) = 0,
    'ni la colonne, ni sa valeur');
end $$;

rollback to savepoint s7;

\echo ''
\echo '=== Tous les tests du flux calendrier sont passés ==='
\echo ''

rollback;
