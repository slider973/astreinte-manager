-- La trace de l'envoi sur l'invitation (migration 0035, ticket 048).
-- Lancement : scripts/test_rls.sh (le script joue tous les supabase/tests/*.sql).
--
-- Ce que ces cas protègent :
--
--   1. le grant de colonne — la trace se lit, `token` toujours pas. Une colonne
--      ajoutée n'hérite pas de l'énumération de 0008 : l'oubli se voit ici ;
--   2. l'étanchéité entre casernes — la trace suit la ligne, et la ligne ne sort
--      pas de sa caserne ni de son cercle d'administrateurs ;
--   3. la sémantique des deux colonnes, et surtout la différence entre « on ne
--      sait pas » (les deux nulles) et « personne n'a été prévenu » (un motif sans
--      date). Confondre les deux serait le mensonge que ce ticket corrige ;
--   4. le rattrapage du § 3 de la migration (cas 5 ci-dessous). Il ne s'observe
--      pas après coup — sur une base remise à zéro, `invitations` est vide quand
--      il passe —, alors on pose le scénario dans un `savepoint` et on **rejoue
--      l'instruction**. C'est une copie littérale de la migration : elle doit être
--      recopiée à chaque retouche du rattrapage, et c'est dit des deux côtés.
--
-- Même méthode que rls_test.sql : pas de pgTAP, une exception fait échouer psql
-- (`ON_ERROR_STOP`). Tout tourne dans une transaction annulée à la fin.

\set ON_ERROR_STOP on
\timing off
\pset pager off
\pset tuples_only on
\pset format unaligned

begin;

create schema tests_trace;

create function tests_trace.check(p_condition boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ECHEC : %', p_label;
  end if;
  raise notice '  ok   %', p_label;
end $$;

-- Une lecture qui doit être refusée par un grant de colonne : l'absence du droit
-- lève `insufficient_privilege`. Les politiques RLS, elles, ne lèvent rien — elles
-- filtrent ; c'est `check(... count = 0 ...)` qui les couvre plus bas.
create function tests_trace.refuse_lecture(p_sql text, p_label text) returns void
language plpgsql as $$
begin
  execute p_sql;
  raise exception 'ECHEC : % — la lecture a été autorisée', p_label;
exception
  when insufficient_privilege then
    raise notice '  ok   %', p_label;
end $$;

-- Les assertions du § 4 sont jouées sous l'identité d'un administrateur : il doit
-- pouvoir appeler l'outillage, sans quoi c'est le test qui échoue, pas la politique.
grant usage on schema tests_trace to authenticated, anon;

\echo ''
\echo '=== La trace de l''envoi sur l''invitation (0035) ==='

-- ===========================================================================
-- 1. Le grant de colonne
-- ===========================================================================
\echo ''
\echo '--- 1. Grants : la trace oui, le jeton non'
savepoint s1;

select tests_trace.check(
  has_column_privilege('authenticated', 'invitations', 'email_sent_at', 'select')
  and has_column_privilege('authenticated', 'invitations', 'email_error', 'select'),
  'un administrateur lit la trace d''envoi de ses invitations');

select tests_trace.check(
  not has_column_privilege('authenticated', 'invitations', 'token', 'select'),
  'le jeton reste hors du grant, colonnes ajoutées ou pas');

select tests_trace.check(
  not has_column_privilege('anon', 'invitations', 'email_sent_at', 'select')
  and not has_column_privilege('anon', 'invitations', 'email_error', 'select'),
  'le rôle anon ne lit rien de la trace');

rollback to savepoint s1;

-- ===========================================================================
-- 2. À la création, on ne sait pas encore
-- ===========================================================================
-- `create_invitation` ne pose pas la trace : elle s'écrit après, au retour de
-- `sendMail`, depuis `invite-member`. Une invitation toute neuve vaut donc « on
-- ne sait pas », et surtout pas « pas envoyé ».
\echo ''
\echo '--- 2. create_invitation laisse la trace vide'
savepoint s2;

do $$
declare r jsonb;
begin
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_trace.check(r->>'ok' = 'true', 'invitation créée');
  perform tests_trace.check(
    (select email_sent_at is null and email_error is null
       from invitations where id = (r#>>'{invitation,id}')::uuid),
    'une invitation qui vient de naître ne prétend ni être partie ni avoir échoué');

  -- Et un renvoi ne réinvente pas la trace non plus : il prolonge la ligne, la
  -- trace attend le résultat de l'envoi.
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  perform tests_trace.check(r->>'resent' = 'true', 'le renvoi réutilise la ligne');
  perform tests_trace.check(
    (select email_sent_at is null and email_error is null
       from invitations where id = (r#>>'{invitation,id}')::uuid),
    'un renvoi ne fabrique pas de trace sans envoi');
end $$;

rollback to savepoint s2;

-- ===========================================================================
-- 3. Les quatre états, relus par l'administrateur de la caserne
-- ===========================================================================
-- Ce que `invite-member` écrit après `sendMail` : un succès pose la date et efface
-- le motif, un échec pose le motif sans toucher à la date.
\echo ''
\echo '--- 3. Ce que les deux colonnes disent'
savepoint s3;

do $$
declare
  r      jsonb;
  v_id   uuid;
begin
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  v_id := (r#>>'{invitation,id}')::uuid;

  -- a) L'échec : personne n'a été prévenu, et on sait pourquoi.
  update invitations
     set email_error = 'aucun fournisseur de courriel configuré'
   where id = v_id;
  perform tests_trace.check(
    (select email_sent_at is null and email_error is not null from invitations where id = v_id),
    'un échec se distingue d''une invitation muette : il porte un motif');

  -- b) Le renvoi qui passe : la date arrive, le motif s'efface.
  update invitations
     set email_sent_at = now(), email_error = null
   where id = v_id;
  perform tests_trace.check(
    (select email_sent_at is not null and email_error is null from invitations where id = v_id),
    'un envoi réussi efface le motif d''échec précédent');

  -- c) Un second renvoi qui échoue : le motif revient, la date du dernier envoi
  --    réussi reste. Les deux faits tiennent ensemble et ne se contredisent pas.
  update invitations
     set email_error = 'resend 422 domaine non vérifié'
   where id = v_id;
  perform tests_trace.check(
    (select email_sent_at is not null and email_error is not null from invitations where id = v_id),
    'un échec de renvoi n''efface pas la date du courriel déjà parti');
end $$;

rollback to savepoint s3;

-- ===========================================================================
-- 4. Étanchéité : la trace ne sort pas de sa caserne
-- ===========================================================================
\echo ''
\echo '--- 4. Qui lit la trace'
savepoint s4;

-- Deux invitations, une par caserne, toutes deux en échec d'envoi.
do $$
declare r jsonb;
begin
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  update invitations set email_error = 'aucun fournisseur de courriel configuré'
   where id = (r#>>'{invitation,id}')::uuid;

  r := create_invitation('bbbbbbbb-0000-4000-8000-000000000001', 'recrue@caserne-b.test',
                         'member', 'bbbbbbbb-0000-4000-8000-000000000100');
  update invitations set email_error = 'aucun fournisseur de courriel configuré'
   where id = (r#>>'{invitation,id}')::uuid;
end $$;

-- a) L'administrateur de la caserne A : sa ligne, et elle seule.
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}';

select tests_trace.check(
  (select count(*) = 1 from invitations
    where email = 'recrue@caserne-a.test' and email_error is not null),
  'l''admin de la caserne A voit que le courriel de son invitation n''est pas parti');

select tests_trace.check(
  (select count(*) = 0 from invitations where email = 'recrue@caserne-b.test'),
  'l''admin de la caserne A ne voit rien de l''invitation de la caserne B');

select tests_trace.refuse_lecture(
  'select token from invitations where email = ''recrue@caserne-a.test''',
  'même administrateur de la caserne, le jeton reste illisible');

rollback to savepoint s4;

savepoint s5;

do $$
declare r jsonb;
begin
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  update invitations set email_error = 'aucun fournisseur de courriel configuré'
   where id = (r#>>'{invitation,id}')::uuid;
end $$;

-- b) L'administrateur de la caserne B : rien du tout, trace comprise.
set local role authenticated;
set local request.jwt.claims = '{"sub":"bbbbbbbb-0000-4000-8000-000000000100","role":"authenticated"}';

select tests_trace.check(
  (select count(*) = 0 from invitations where station_id = 'aaaaaaaa-0000-4000-8000-000000000001'),
  'l''admin de la caserne B ne lit aucune invitation de la caserne A');

rollback to savepoint s5;

savepoint s6;

do $$
declare r jsonb;
begin
  r := create_invitation('aaaaaaaa-0000-4000-8000-000000000001', 'recrue@caserne-a.test',
                         'member', 'aaaaaaaa-0000-4000-8000-000000000100');
  update invitations set email_error = 'aucun fournisseur de courriel configuré'
   where id = (r#>>'{invitation,id}')::uuid;
end $$;

-- c) Un membre simple de la caserne A : l'invitation n'est pas son affaire, la
--    trace non plus.
set local role authenticated;
set local request.jwt.claims = '{"sub":"aaaaaaaa-0000-4000-8000-000000000101","role":"authenticated"}';

select tests_trace.check(
  (select count(*) = 0 from invitations),
  'un membre simple ne lit aucune invitation, ni sa trace d''envoi');

rollback to savepoint s6;

-- ===========================================================================
-- 5. Le rattrapage du § 3 de la migration
-- ===========================================================================
-- On pose ce que la production avait au moment du déploiement — des invitations
-- en attente, et les `notifications` qui gardent la trace de leurs envois — puis
-- on **rejoue l'instruction de la migration, à la lettre**, et on relit.
--
-- Le cas qui compte est le a) : un envoi réussi, puis un renvoi qui échoue. Une
-- version du rattrapage qui prend les deux colonnes sur la même dernière ligne
-- écrit `(nul, motif)`, c'est-à-dire « personne n'a été prévenu », à une personne
-- qui a reçu son invitation neuf jours plus tôt. Les deux colonnes se calculent
-- séparément : la date est le dernier envoi **réussi**, le motif est celui de la
-- ligne la plus récente — ce que fait `_shared/invitation_trace.ts`.
\echo ''
\echo '--- 5. Le rattrapage des invitations antérieures'
savepoint s7;

create function tests_trace.poser_invitation(
  p_station uuid, p_email text, p_invited_by uuid, p_age interval,
  p_acceptee boolean default false) returns uuid
language plpgsql as $$
declare v_id uuid;
begin
  insert into invitations (station_id, email, role, invited_by, created_at, expires_at, accepted_at)
  values (p_station, p_email, 'member', p_invited_by, now() - p_age,
          now() + interval '14 days',
          case when p_acceptee then now() - interval '1 hour' end)
  returning id into v_id;
  return v_id;
end $$;

-- Une ligne de `notifications` telle que `tracerNotification` l'écrit : un succès
-- porte `sent_at`, un échec porte `error` et laisse `sent_at` nul.
create function tests_trace.poser_notification(
  p_station uuid, p_user uuid, p_age interval, p_reussi boolean,
  p_error text default null) returns void
language plpgsql as $$
begin
  insert into notifications (station_id, user_id, type, channel, title, body, sent_at, error, created_at)
  values (p_station, p_user, 'invitation', 'email', 'Invitation', 'Rejoignez la caserne',
          case when p_reussi then now() - p_age end,
          case when p_reussi then null else coalesce(p_error, 'envoi impossible') end,
          now() - p_age);
end $$;

do $$
declare
  v_a       uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
  v_b       uuid := 'bbbbbbbb-0000-4000-8000-000000000001';
  v_admin_a uuid := 'aaaaaaaa-0000-4000-8000-000000000100';
begin
  -- a) Parti il y a 9 jours, renvoi échoué il y a 1 jour. Le cas du bloquant.
  perform tests_trace.poser_invitation(v_a, 'membre7@caserne-a.test', v_admin_a, interval '20 days');
  perform tests_trace.poser_notification(v_a, 'aaaaaaaa-0000-4000-8000-000000000107', interval '9 days', true);
  perform tests_trace.poser_notification(v_a, 'aaaaaaaa-0000-4000-8000-000000000107', interval '1 day', false,
                                         'resend 422 domaine non vérifié');

  -- b) Un seul envoi, réussi.
  perform tests_trace.poser_invitation(v_a, 'membre6@caserne-a.test', v_admin_a, interval '20 days');
  perform tests_trace.poser_notification(v_a, 'aaaaaaaa-0000-4000-8000-000000000106', interval '3 days', true);

  -- c) Un seul envoi, échoué : personne n'a été prévenu.
  perform tests_trace.poser_invitation(v_a, 'membre5@caserne-a.test', v_admin_a, interval '20 days');
  perform tests_trace.poser_notification(v_a, 'aaaaaaaa-0000-4000-8000-000000000105', interval '2 days', false,
                                         'aucun fournisseur de courriel configuré');

  -- d) Échoué il y a 5 jours, puis parti il y a 1 jour : le succès efface le motif.
  perform tests_trace.poser_invitation(v_a, 'membre4@caserne-a.test', v_admin_a, interval '20 days');
  perform tests_trace.poser_notification(v_a, 'aaaaaaaa-0000-4000-8000-000000000104', interval '5 days', false,
                                         'smtp 421 service indisponible');
  perform tests_trace.poser_notification(v_a, 'aaaaaaaa-0000-4000-8000-000000000104', interval '1 day', true);

  -- e) Aucune notification : on ne sait pas, et on n'invente rien.
  perform tests_trace.poser_invitation(v_a, 'membre3@caserne-a.test', v_admin_a, interval '20 days');

  -- f) Une notification antérieure à l'invitation : c'est l'envoi d'une invitation
  --    précédente, supprimée puis recréée. Elle ne compte pas.
  perform tests_trace.poser_invitation(v_a, 'membre2@caserne-a.test', v_admin_a, interval '2 days');
  perform tests_trace.poser_notification(v_a, 'aaaaaaaa-0000-4000-8000-000000000102', interval '10 days', true);

  -- g) Une notification de l'autre caserne pour la même personne : elle non plus.
  perform tests_trace.poser_invitation(v_a, 'membre1@caserne-b.test', v_admin_a, interval '20 days');
  perform tests_trace.poser_notification(v_b, 'bbbbbbbb-0000-4000-8000-000000000101', interval '4 days', true);

  -- h) Une invitation déjà acceptée : hors du rattrapage, l'écran ne l'affiche pas.
  perform tests_trace.poser_invitation(v_a, 'membre1@caserne-a.test', v_admin_a, interval '20 days', true);
  perform tests_trace.poser_notification(v_a, 'aaaaaaaa-0000-4000-8000-000000000101', interval '6 days', false,
                                         'aucun fournisseur de courriel configuré');
end $$;

-- >>> Copie littérale du § 3 de supabase/migrations/0035_trace_envoi_invitation.sql.
with trace_connue as (
  select i.id                                                            as invitation_id,
         max(n.sent_at)                                                  as sent_at,
         (array_agg(n.error order by n.created_at desc, n.id desc))[1]   as error
    from invitations i
    join profiles p on lower(p.email) = lower(i.email)
    join notifications n
      on n.user_id    = p.id
     and n.station_id = i.station_id
     and n.type       = 'invitation'
     and n.channel    = 'email'
     and n.created_at >= i.created_at
   where i.accepted_at is null
   group by i.id
)
update invitations i
   set email_sent_at = t.sent_at,
       email_error   = left(t.error, 300)
  from trace_connue t
 where t.invitation_id = i.id
   and (t.sent_at is not null or t.error is not null);
-- <<< Fin de la copie.

do $$
declare r record;
begin
  -- a) Les deux faits tiennent ensemble, et la date est celle du succès.
  select * into r from invitations where email = 'membre7@caserne-a.test';
  perform tests_trace.check(
    r.email_sent_at is not null and r.email_error = 'resend 422 domaine non vérifié',
    'un envoi réussi puis un renvoi échoué : la ligne garde la date **et** dit le dernier échec');
  perform tests_trace.check(
    r.email_sent_at between now() - interval '9 days' - interval '1 minute'
                        and now() - interval '9 days' + interval '1 minute',
    'la date rattrapée est celle du dernier envoi réussi, pas celle du renvoi raté');

  -- b) Le succès seul.
  select * into r from invitations where email = 'membre6@caserne-a.test';
  perform tests_trace.check(
    r.email_sent_at is not null and r.email_error is null,
    'un envoi réussi rattrape la date, sans motif d''échec');

  -- c) L'échec seul : personne n'a été prévenu, et on sait pourquoi.
  select * into r from invitations where email = 'membre5@caserne-a.test';
  perform tests_trace.check(
    r.email_sent_at is null and r.email_error = 'aucun fournisseur de courriel configuré',
    'un envoi échoué rattrape le motif, sans date');

  -- d) L'effacement, comme le fait invitation_trace.ts.
  select * into r from invitations where email = 'membre4@caserne-a.test';
  perform tests_trace.check(
    r.email_sent_at is not null and r.email_error is null,
    'un échec suivi d''un succès : le succès efface le motif');

  -- e), f), g), h) Les silences restent des silences.
  select * into r from invitations where email = 'membre3@caserne-a.test';
  perform tests_trace.check(
    r.email_sent_at is null and r.email_error is null,
    'sans notification appariée, l''invitation reste à « on ne sait pas »');

  select * into r from invitations where email = 'membre2@caserne-a.test';
  perform tests_trace.check(
    r.email_sent_at is null and r.email_error is null,
    'une notification antérieure à l''invitation ne lui est pas attribuée');

  select * into r from invitations where email = 'membre1@caserne-b.test';
  perform tests_trace.check(
    r.email_sent_at is null and r.email_error is null,
    'une notification de l''autre caserne ne rattrape rien');

  select * into r from invitations where email = 'membre1@caserne-a.test';
  perform tests_trace.check(
    r.email_sent_at is null and r.email_error is null,
    'une invitation déjà acceptée reste hors du rattrapage');
end $$;

rollback to savepoint s7;

rollback;
