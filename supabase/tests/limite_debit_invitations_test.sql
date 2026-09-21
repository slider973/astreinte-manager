-- Tests du plafond de débit des invitations (migration 0032, ticket 038).
-- Lancement : scripts/test_rls.sh (le script joue tous les supabase/tests/*.sql).
--
-- Ce qui est vérifié, section par section
-- ---------------------------------------
-- 1. Le réglage : `invitation_hourly_limit` accepté dans ses bornes, refusé en
--    dehors, **facultatif** — et les casernes écrites avant 0032 restent
--    modifiables, ce qui est la seule façon de prouver qu'aucune migration
--    future ne se cassera dessus.
-- 2. Le compteur : une ligne par courriel qui part, création **et** renvoi.
-- 3. Le lot : vingt adresses en un envoi comptent pour vingt, pas pour un.
-- 4. Le refus : code `rate_limited`, délai de réessai juste, et rien d'écrit.
-- 5. La fenêtre glissante qui se vide.
-- 6. Le super-administrateur : plafond plus haut, compté par acteur.
-- 7. Le journal d'audit : le dépassement est tracé, une fois par fenêtre.
-- 8. La RLS de `invitation_rate_events` : la caserne A ne voit rien de la B.
-- 9. La purge.
--
-- Méthode identique aux autres fichiers du dossier : pas de pgTAP, une exception
-- fait sortir psql avec un code non nul, le tout dans une transaction annulée.
--
-- Fixtures : le seed (caserne A = aaaaaaaa-…-001, admin …100, membre …101 ;
-- caserne B = bbbbbbbb-…-001, admin …100), plus un compte hors seed qui joue
-- l'éditeur du produit, membre d'aucune caserne.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests_deb;

create function tests_deb.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

-- L'écriture doit être refusée : soit erreur RLS, soit 0 ligne touchée (une
-- politique USING qui ne matche pas filtre silencieusement).
create function tests_deb.denied(p_sql text, p_label text) returns void
language plpgsql as $$
declare n integer;
begin
  execute p_sql;
  get diagnostics n = row_count;
  if n > 0 then
    raise exception 'ECHEC : % — % ligne(s) écrite(s) alors que l''écriture devait être refusée', p_label, n;
  end if;
  raise notice '  ok   %  (0 ligne)', p_label;
exception
  when insufficient_privilege then
    raise notice '  ok   %  (refus RLS)', p_label;
end $$;

grant usage on schema tests_deb to authenticated, anon;
grant execute on all functions in schema tests_deb to authenticated, anon;

\set caserne_a '''aaaaaaaa-0000-4000-8000-000000000001'''
\set caserne_b '''bbbbbbbb-0000-4000-8000-000000000001'''
\set admin_a   '''aaaaaaaa-0000-4000-8000-000000000100'''
\set membre_a  '''aaaaaaaa-0000-4000-8000-000000000101'''
\set admin_b   '''bbbbbbbb-0000-4000-8000-000000000100'''
\set editeur   '''eeeeeeee-0000-4000-8000-0000000000f1'''

insert into auth.users (
  instance_id, id, aud, role, email, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new, email_change_token_current
) values (
  '00000000-0000-0000-0000-000000000000',
  :editeur::uuid,
  'authenticated', 'authenticated', 'editeur-038@astreinte.test', now(),
  '{"provider": "email", "providers": ["email"]}'::jsonb, '{}'::jsonb, now(), now(),
  '', '', '', '', ''
);
insert into super_admins (user_id) values (:editeur::uuid);

\echo ''
\echo '=== Plafond de débit des invitations (0032) ==='

-- ===========================================================================
-- 1. Le réglage dans les paramètres de la caserne
-- ===========================================================================
\echo ''
\echo '--- 1. settings.invitation_hourly_limit'
savepoint s1;

do $$
declare
  base constant jsonb := (select settings from stations where id = 'aaaaaaaa-0000-4000-8000-000000000001');
begin
  -- Le défaut s'applique quand la clé est absente : c'est le cas de toutes les
  -- casernes du seed, et de toutes celles créées avant cette migration.
  perform tests_deb.check(
    not (base ? 'invitation_hourly_limit'),
    'la caserne du seed ne porte pas encore la clé');
  perform tests_deb.check(
    station_invitation_hourly_limit('aaaaaaaa-0000-4000-8000-000000000001') = 60,
    'clé absente : le plafond vaut 60 par défaut');
  perform tests_deb.check(
    station_invitation_hourly_limit('dddddddd-0000-4000-8000-0000000000ff') = 60,
    'caserne inconnue : le plafond par défaut, jamais NULL');

  -- La liste blanche de 0011 connaît la clé…
  perform tests_deb.check(
    station_settings_valid(base || '{"invitation_hourly_limit": 30}'::jsonb),
    'la clé est acceptée par station_settings_valid');
  perform tests_deb.check(
    station_settings_valid(base || '{"invitation_hourly_limit": 1}'::jsonb),
    'borne basse : 1 accepté');
  perform tests_deb.check(
    station_settings_valid(base || '{"invitation_hourly_limit": 500}'::jsonb),
    'borne haute : 500 accepté');

  -- … et ses bornes.
  perform tests_deb.check(
    not station_settings_valid(base || '{"invitation_hourly_limit": 0}'::jsonb),
    'zéro refusé : un plafond nul n''est pas un débit');
  perform tests_deb.check(
    not station_settings_valid(base || '{"invitation_hourly_limit": 501}'::jsonb),
    'au-delà de 500 : refusé');
  perform tests_deb.check(
    not station_settings_valid(base || '{"invitation_hourly_limit": 12.5}'::jsonb),
    'un décimal refusé');
  perform tests_deb.check(
    not station_settings_valid(base || '{"invitation_hourly_limit": "beaucoup"}'::jsonb),
    'une chaîne refusée');
  perform tests_deb.check(
    not station_settings_valid(base || '{"invitation_hourly_limits": 30}'::jsonb),
    'la liste blanche tient toujours : une clé mal orthographiée est refusée');

  -- **Le point qui casserait une migration future** : la contrainte
  -- `stations_settings_valide` est rejouée à chaque écriture d'une ligne. Une
  -- clé obligatoire aurait condamné toutes les casernes déjà écrites.
  perform tests_deb.check(
    not exists (select 1 from stations s where not station_settings_valid(s.settings)),
    'toutes les casernes existantes restent valides');
end $$;

-- L'écriture elle-même, pour que ce soit la contrainte qui parle et pas la
-- fonction seule : une caserne sans la clé se met encore à jour.
update stations set timezone = timezone
 where id = :caserne_a::uuid;

update stations set settings = settings || '{"invitation_hourly_limit": 5}'::jsonb
 where id = :caserne_a::uuid;

do $$
begin
  perform tests_deb.check(
    station_invitation_hourly_limit('aaaaaaaa-0000-4000-8000-000000000001') = 5,
    'le plafond écrit est celui qui s''applique');
end $$;

do $$
begin
  begin
    update stations set settings = settings || '{"invitation_hourly_limit": 9000}'::jsonb
     where id = 'aaaaaaaa-0000-4000-8000-000000000001';
    raise exception 'ECHEC : la contrainte a laissé passer un plafond hors bornes';
  exception
    when check_violation then
      raise notice '  ok   la contrainte refuse un plafond hors bornes';
  end;
end $$;

rollback to savepoint s1;

-- ===========================================================================
-- 2. Le compteur : une ligne par courriel qui part
-- ===========================================================================
\echo ''
\echo '--- 2. invitation_rate_events : création et renvoi'
savepoint s2;

do $$
declare r jsonb;
begin
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue1@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_deb.check((r->>'ok')::boolean, 'première invitation acceptée');
  perform tests_deb.check(
    (select count(*) from invitation_rate_events
      where station_id = 'aaaaaaaa-0000-4000-8000-000000000001') = 1,
    'une invitation crée une ligne de compteur');
  perform tests_deb.check(
    (select actor_id from invitation_rate_events limit 1)
      = 'aaaaaaaa-0000-4000-8000-000000000100',
    'la ligne porte l''acteur, pas l''invité');

  -- Un renvoi réutilise la ligne d'invitation mais **envoie un courriel** : il
  -- compte. C'est le contournement le plus évident du plafond.
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue1@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_deb.check((r->>'resent')::boolean, 'seconde invitation : un renvoi');
  perform tests_deb.check(
    (select count(*) from invitations
      where station_id = 'aaaaaaaa-0000-4000-8000-000000000001') = 1,
    'le renvoi n''a pas créé de seconde invitation');
  perform tests_deb.check(
    (select count(*) from invitation_rate_events
      where station_id = 'aaaaaaaa-0000-4000-8000-000000000001') = 2,
    'le renvoi compte pour un envoi');

  -- Un refus qui n'envoie rien ne consomme rien.
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'pas-une-adresse',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_deb.check(r->>'code' = 'invalid_email', 'adresse invalide refusée');
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'membre1@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_deb.check(r->>'code' = 'already_member', 'membre déjà actif refusé');
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue2@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000101');
  perform tests_deb.check(r->>'code' = 'not_admin', 'un membre simple n''invite pas');

  perform tests_deb.check(
    (select count(*) from invitation_rate_events) = 2,
    'aucun refus n''a consommé de budget : le plafond protège l''envoi');

  -- Le compteur d'une caserne ne déborde pas sur sa voisine.
  r := create_invitation('bbbbbbbb-0000-4000-8000-000000000001', 'recrue1@caserne-b.test',
                         'member', 'bbbbbbbb-0000-4000-8000-000000000100');
  perform tests_deb.check((r->>'ok')::boolean, 'la caserne B invite de son côté');
  perform tests_deb.check(
    (invitation_rate_limit('aaaaaaaa-0000-4000-8000-000000000001',
                           'aaaaaaaa-0000-4000-8000-000000000100') ->> 'used')::int = 2,
    'la caserne A compte 2, l''envoi de la B ne l''a pas touchée');
  perform tests_deb.check(
    (invitation_rate_limit('bbbbbbbb-0000-4000-8000-000000000001',
                           'bbbbbbbb-0000-4000-8000-000000000100') ->> 'used')::int = 1,
    'la caserne B compte 1');
end $$;

rollback to savepoint s2;

-- ===========================================================================
-- 3. Le lot : vingt adresses comptent pour vingt
-- ===========================================================================
-- C'est le contournement le plus rentable : l'Edge Function accepte vingt
-- adresses par appel, et un compteur qui compterait les appels laisserait passer
-- vingt fois le plafond.
\echo ''
\echo '--- 3. un lot de vingt adresses'
savepoint s3;

update stations set settings = settings || '{"invitation_hourly_limit": 20}'::jsonb
 where id = :caserne_a::uuid;

do $$
declare
  r jsonb;
  i integer;
begin
  for i in 1..20 loop
    r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001',
                           format('recrue%s@caserne-a.test', i),
                           'member', 'aaaaaaaa-0000-4000-8000-000000000100');
    perform tests_deb.check((r->>'ok')::boolean, format('adresse %s du lot acceptée', i));
  end loop;

  perform tests_deb.check(
    (select count(*) from invitation_rate_events
      where station_id = 'aaaaaaaa-0000-4000-8000-000000000001') = 20,
    'un lot de vingt adresses compte pour vingt, pas pour un');

  -- Le plafond vaut 20 : la vingt-et-unième adresse tombe, dans le même lot
  -- comme dans l'appel suivant.
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue21@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_deb.check(r->>'code' = 'rate_limited',
    'la vingt-et-unième adresse est refusée');
  perform tests_deb.check(
    (select count(*) from invitations where lower(email) = 'recrue21@caserne-a.test') = 0,
    'l''adresse refusée n''a laissé aucune invitation');
end $$;

rollback to savepoint s3;

-- ===========================================================================
-- 4. Le refus : le code, le délai, et rien d'écrit
-- ===========================================================================
\echo ''
\echo '--- 4. le refus au-delà du plafond'
savepoint s4;

update stations set settings = settings || '{"invitation_hourly_limit": 2}'::jsonb
 where id = :caserne_a::uuid;

do $$
declare
  r        jsonb;
  avant    integer;
  d        jsonb;
begin
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue1@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_deb.check((r->>'ok')::boolean, 'premier envoi accepté');
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue2@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_deb.check((r->>'ok')::boolean, 'second envoi accepté : le plafond est atteint, pas franchi');

  d := invitation_rate_limit('aaaaaaaa-0000-4000-8000-000000000001',
                             'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_deb.check((d->>'allowed')::boolean is false, 'le plafond est atteint');
  perform tests_deb.check((d->>'remaining')::int = 0, 'il ne reste rien');

  avant := (select count(*) from invitations);

  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue3@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_deb.check(r->>'code' = 'rate_limited',
    'au-delà du plafond, create_invitation refuse avec le code rate_limited');
  perform tests_deb.check((r->>'ok')::boolean is false, 'le refus est un refus');
  perform tests_deb.check((r->>'limit')::int = 2, 'le refus dit le plafond');
  perform tests_deb.check((r->>'used')::int = 2, 'le refus dit ce qui a été consommé');
  perform tests_deb.check((r->>'window_minutes')::int = 60, 'la fenêtre fait une heure');
  perform tests_deb.check(r->>'scope' = 'station', 'la portée est la caserne');
  perform tests_deb.check(r ? 'retry_at', 'le refus dit quand réessayer');
  perform tests_deb.check(
    (r->>'retry_after_seconds')::int between 1 and 3600,
    'le délai de réessai tient dans la fenêtre');
  perform tests_deb.check(not (r ? 'token'),
    'un refus ne rend jamais de jeton');

  perform tests_deb.check((select count(*) from invitations) = avant,
    'l''adresse refusée n''a créé aucune invitation');
  perform tests_deb.check(
    (select count(*) from invitation_rate_events) = 2,
    'un refus ne consomme pas de budget : sinon le plafond ne se relâcherait jamais');

  -- Le délai est **exact**, pas « dans une heure ». Deux envois vieux de
  -- cinquante minutes : la place se libère dans dix.
  update invitation_rate_events set created_at = now() - interval '50 minutes';
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue4@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_deb.check(r->>'code' = 'rate_limited', 'toujours refusé à cinquante minutes');
  perform tests_deb.check(
    (r->>'retry_after_seconds')::int between 570 and 630,
    'le délai annoncé est celui de la place qui se libère, environ dix minutes');
end $$;

rollback to savepoint s4;

-- ===========================================================================
-- 5. La fenêtre glissante se vide
-- ===========================================================================
\echo ''
\echo '--- 5. la fenêtre qui se vide'
savepoint s5;

update stations set settings = settings || '{"invitation_hourly_limit": 2}'::jsonb
 where id = :caserne_a::uuid;

do $$
declare r jsonb;
begin
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue1@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue2@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue3@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_deb.check(r->>'code' = 'rate_limited', 'plafond atteint');

  -- Un seul envoi sort de la fenêtre : une place, et une seule.
  update invitation_rate_events set created_at = now() - interval '61 minutes'
   where id = (select id from invitation_rate_events order by created_at asc limit 1);

  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue3@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_deb.check((r->>'ok')::boolean,
    'une place libérée : l''envoi suivant passe');
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue4@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_deb.check(r->>'code' = 'rate_limited',
    'et une seule : le suivant est de nouveau refusé');

  -- Toute la fenêtre se vide : tout repart.
  update invitation_rate_events set created_at = now() - interval '2 hours';
  perform tests_deb.check(
    (invitation_rate_limit('aaaaaaaa-0000-4000-8000-000000000001',
                           'aaaaaaaa-0000-4000-8000-000000000100') ->> 'used')::int = 0,
    'une heure plus tard, le compteur est vide');
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue4@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_deb.check((r->>'ok')::boolean, 'et la caserne réinvite');
end $$;

rollback to savepoint s5;

-- ===========================================================================
-- 6. Le super-administrateur : plafond plus haut, compté par acteur
-- ===========================================================================
-- Il nomme le premier administrateur d'une caserne **qu'il vient de créer**
-- (ticket 031). Un compteur par caserne ne le mesurerait jamais : il repart de
-- zéro à chaque caserne neuve.
\echo ''
\echo '--- 6. le super-administrateur'
savepoint s6;

update stations set settings = settings || '{"invitation_hourly_limit": 1}'::jsonb
 where id = :caserne_a::uuid;

do $$
declare
  r jsonb;
  d jsonb;
  i integer;
begin
  -- La caserne A épuise son budget d'une invitation.
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue1@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_deb.check((r->>'ok')::boolean, 'la caserne A consomme son unique envoi');
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue2@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_deb.check(r->>'code' = 'rate_limited', 'et son administrateur est bloqué');

  -- L'éditeur, lui, n'est pas mesuré à l'aune de la caserne.
  d := invitation_rate_limit('aaaaaaaa-0000-4000-8000-000000000001',
                             'eeeeeeee-0000-4000-8000-0000000000f1');
  perform tests_deb.check(d->>'scope' = 'actor',
    'le super-administrateur est compté par acteur');
  perform tests_deb.check((d->>'limit')::int = 200,
    'son plafond est plus élevé que celui d''une caserne');
  perform tests_deb.check((d->>'allowed')::boolean,
    'il peut inviter dans une caserne dont le budget est épuisé');

  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'premier-admin@caserne-a.test',
                         'admin', 'eeeeeeee-0000-4000-8000-0000000000f1');
  perform tests_deb.check((r->>'ok')::boolean,
    'il nomme le premier administrateur malgré le plafond de la caserne');

  d := invitation_rate_limit('aaaaaaaa-0000-4000-8000-000000000001',
                             'eeeeeeee-0000-4000-8000-0000000000f1');
  perform tests_deb.check((d->>'used')::int = 1,
    'son propre compteur avance, lui');

  -- Et il finit par être plafonné, lui aussi : « plus haut » n'est pas
  -- « sans limite ». 199 envois posés à la main, plus le sien, font 200.
  insert into invitation_rate_events (station_id, actor_id)
  select 'bbbbbbbb-0000-4000-8000-000000000001'::uuid,
         'eeeeeeee-0000-4000-8000-0000000000f1'::uuid
  from generate_series(1, 199);

  d := invitation_rate_limit('aaaaaaaa-0000-4000-8000-000000000001',
                             'eeeeeeee-0000-4000-8000-0000000000f1');
  perform tests_deb.check((d->>'used')::int = 200,
    'ses envois se comptent toutes casernes confondues');
  perform tests_deb.check((d->>'allowed')::boolean is false,
    'le super-administrateur a un plafond, plus haut mais réel');

  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue9@caserne-a.test',
                         'member', 'eeeeeeee-0000-4000-8000-0000000000f1');
  perform tests_deb.check(r->>'code' = 'rate_limited',
    'et il est refusé comme les autres');
  perform tests_deb.check(r->>'scope' = 'actor',
    'le refus dit que la portée est son compte, pas la caserne');
end $$;

rollback to savepoint s6;

-- ===========================================================================
-- 7. Le journal d'audit
-- ===========================================================================
\echo ''
\echo '--- 7. le dépassement est journalisé'
savepoint s7;

update stations set settings = settings || '{"invitation_hourly_limit": 1}'::jsonb
 where id = :caserne_a::uuid;

delete from audit_log where station_id = :caserne_a::uuid;

do $$
declare
  r     jsonb;
  ligne audit_log%rowtype;
  i     integer;
begin
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue1@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_deb.check((r->>'ok')::boolean, 'le premier envoi passe');

  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue2@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_deb.check(r->>'code' = 'rate_limited', 'le second est refusé');

  select * into ligne from audit_log
   where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
     and action = 'invitation.rate_limited';
  perform tests_deb.check(found, 'le dépassement est inscrit au journal d''audit');
  perform tests_deb.check(ligne.actor_id = 'aaaaaaaa-0000-4000-8000-000000000100',
    'le journal nomme l''acteur');
  perform tests_deb.check(ligne.entity = 'invitations', 'le journal nomme l''entité');
  perform tests_deb.check((ligne.data->>'limit')::int = 1,
    'le journal garde le plafond en vigueur');
  perform tests_deb.check((ligne.data->>'used')::int = 1,
    'le journal garde le compte atteint');
  perform tests_deb.check(ligne.data ? 'retry_at',
    'le journal garde la date de réessai');
  perform tests_deb.check(ligne.data->>'email' = 'recrue2@caserne-a.test',
    'le journal garde l''adresse qui a déclenché le refus');
  perform tests_deb.check(not (ligne.data ? 'allowed'),
    'le journal ne garde pas le booléen : la ligne dit déjà qu''on a refusé');

  -- Un lot de vingt refus n'écrit pas vingt fois la même phrase.
  for i in 3..22 loop
    r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001',
                           format('recrue%s@caserne-a.test', i),
                           'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  end loop;

  perform tests_deb.check(
    (select count(*) from audit_log
      where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'
        and action = 'invitation.rate_limited') = 1,
    'une seule ligne de dépassement par caserne et par fenêtre, malgré vingt refus');

  -- La caserne voisine a son propre journal.
  perform tests_deb.check(
    (select count(*) from audit_log
      where station_id = 'bbbbbbbb-0000-4000-8000-000000000001'
        and action = 'invitation.rate_limited') = 0,
    'rien n''a été écrit dans le journal de la caserne B');
end $$;

rollback to savepoint s7;

-- ===========================================================================
-- 8. La RLS de invitation_rate_events
-- ===========================================================================
\echo ''
\echo '--- 8. la caserne A ne voit rien des compteurs de la caserne B'
savepoint s8;

insert into invitation_rate_events (station_id, actor_id) values
  (:caserne_a::uuid, :admin_a::uuid),
  (:caserne_a::uuid, :admin_a::uuid),
  (:caserne_b::uuid, :admin_b::uuid);

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

do $$
begin
  perform tests_deb.check(
    (select count(*) from invitation_rate_events) = 2,
    'l''admin de la caserne A voit les deux compteurs de sa caserne');
  perform tests_deb.check(
    not exists (select 1 from invitation_rate_events
                 where station_id = 'bbbbbbbb-0000-4000-8000-000000000001'),
    'et rien de la caserne B');
end $$;

select tests_deb.denied(
  $$insert into invitation_rate_events (station_id, actor_id)
    values ('aaaaaaaa-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000100')$$,
  'un admin ne pose pas de ligne de compteur à la main');
select tests_deb.denied(
  $$delete from invitation_rate_events$$,
  'un admin n''efface pas son compteur');
select tests_deb.denied(
  $$update invitation_rate_events set created_at = now() - interval '2 hours'$$,
  'un admin ne fait pas reculer son compteur');

do $$
begin
  perform tests_deb.check(
    not has_function_privilege('authenticated',
      'public.invitation_rate_limit(uuid, uuid, timestamptz)', 'execute'),
    'invitation_rate_limit n''est pas exécutable par un client authentifié');
  perform tests_deb.check(
    not has_function_privilege('anon',
      'public.invitation_rate_limit(uuid, uuid, timestamptz)', 'execute'),
    'ni par un anonyme');
  perform tests_deb.check(
    not has_function_privilege('authenticated',
      'public.prune_invitation_rate_events(timestamptz, integer)', 'execute'),
    'la purge non plus');
end $$;

set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

do $$
begin
  perform tests_deb.check(
    (select count(*) from invitation_rate_events) = 0,
    'un membre simple ne voit aucun compteur, même celui de sa caserne');
end $$;

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

do $$
begin
  perform tests_deb.check(
    not has_table_privilege('anon', 'public.invitation_rate_events', 'select'),
    'anon n''a aucun privilège sur la table');
end $$;

reset role;
reset request.jwt.claims;

rollback to savepoint s8;

-- ===========================================================================
-- 9. La purge
-- ===========================================================================
\echo ''
\echo '--- 9. prune_invitation_rate_events'
savepoint s9;

insert into invitation_rate_events (station_id, actor_id, created_at) values
  (:caserne_a::uuid, :admin_a::uuid, now() - interval '30 minutes'),
  (:caserne_a::uuid, :admin_a::uuid, now() - interval '6 days 23 hours'),
  (:caserne_a::uuid, :admin_a::uuid, now() - interval '7 days 1 hour'),
  (:caserne_b::uuid, :admin_b::uuid, now() - interval '30 days');

do $$
begin
  perform tests_deb.check(prune_invitation_rate_events() = 2,
    'la purge emporte les lignes de plus de sept jours');
  perform tests_deb.check(
    (select count(*) from invitation_rate_events) = 2,
    'et laisse la semaine en cours');
  perform tests_deb.check(prune_invitation_rate_events() = 0,
    'rejouée, elle n''a plus rien à faire');

  -- La frontière à la journée près, comme les autres purges de 0030.
  perform tests_deb.check(
    prune_invitation_rate_events(now(), 0) = 2,
    'p_days = 0 emporte tout ce qui date d''avant l''instant de référence');

  -- Et elle est branchée sur la tâche hebdomadaire.
  perform tests_deb.check(
    cron_prune_retention() ? 'invitation_rate_events',
    'cron_prune_retention applique la durée de conservation du compteur');
end $$;

rollback to savepoint s9;

\echo ''
\echo '=== Plafond de débit des invitations : tous les tests sont passés ==='

rollback;
