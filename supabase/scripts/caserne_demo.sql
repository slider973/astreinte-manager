-- Caserne de démonstration — Astreinte SP (ticket 076).
--
-- Crée, ou remet à zéro, « CIS Démonstration » : la caserne que voit le relecteur
-- d'Apple (revue bêta TestFlight) et, plus tard, celui de l'App Store. Ce n'est
-- PAS une migration : ce sont des données, rejouées à la main avant chaque revue
-- pour que les dates restent fraîches (mois courant, M+1, M+2).
--
--   supabase db query --local -f supabase/scripts/caserne_demo.sql
--   supabase db query --linked --project-ref <ref> -f supabase/scripts/caserne_demo.sql
--
-- Puis le mot de passe du compte de revue, par l'API d'administration Auth, depuis
-- 1Password (docs/IOS.md § 10) : il n'est jamais dans ce fichier ni dans le dépôt.
--
-- Ce que le script garantit :
--   - il ne touche qu'à la caserne d'identifiant fixe ci-dessous, et refuse de
--     tourner si son slug est déjà pris par une autre caserne ;
--   - aucune donnée réelle : les membres fictifs n'ont **pas** de compte
--     d'authentification (un profil seul, comme un compte supprimé — § 2.2 de
--     docs/SCHEMA.md) et leur adresse est en `.invalid` (RFC 2606), qui ne
--     reçoit jamais rien ;
--   - le seul compte qui puisse se connecter est le compte de revue, simple
--     membre ; créé s'il manque, gardé tel quel s'il existe (son mot de passe
--     survit à la remise à zéro) ;
--   - abonnement `active` sans date de fin : la caserne ne passe jamais en
--     lecture seule ;
--   - règles RLS et déclencheurs inchangés : deux gardes de suppression sont
--     levées le temps de la transaction (DDL transactionnel, personne d'autre
--     ne les voit levées), parce qu'un planning publié ne se supprime pas
--     autrement — c'est voulu pour une vraie caserne, pas pour celle-ci.
--
-- Contenu, recalculé depuis now() à chaque passage :
--   - mois courant : planning validé, toutes les astreintes acceptées ;
--   - M+1 : saisie verrouillée, planning publié, propositions **en attente**
--     pour le compte de revue (à accepter ou refuser) ;
--   - M+2 : saisie ouverte, rien de saisi par le compte de revue ;
--   - deux notifications dans le centre du compte de revue.

begin;

-- ---------------------------------------------------------------------------
-- 0. Identifiants fixes et garde
-- ---------------------------------------------------------------------------
create temp table demo_const on commit drop as
select
  'de300000-0000-4000-8000-000000000001'::uuid as station_id,
  'demonstration'::text                        as slug,
  'revue-apple@astreinte-sp.fr'::text          as review_email,
  'de300000-0000-4000-8000-000000000100'::uuid as review_new_id,
  'de300000-0000-4000-8000-000000000110'::uuid as chef_id;

do $$
begin
  if exists (
    select 1 from stations s, demo_const c
     where s.slug = c.slug and s.id <> c.station_id
  ) then
    raise exception 'caserne_demo_slug_pris'
      using hint = 'Le slug « demonstration » appartient à une autre caserne : rien n''est modifié.';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1. La caserne et son abonnement
-- ---------------------------------------------------------------------------
insert into stations (id, name, slug, timezone, settings)
select c.station_id, 'CIS Démonstration', c.slug, 'Europe/Paris',
       '{"day_start": "07:00", "day_end": "19:00",
         "required_day": 2, "required_night": 2,
         "availability_deadline_day": 15,
         "response_reminder_hours": 24, "response_email_hours": 48,
         "late_report_hours": 72}'::jsonb
from demo_const c
on conflict (id) do update
   set name = excluded.name, slug = excluded.slug,
       timezone = excluded.timezone, settings = excluded.settings;

-- Le déclencheur de création a pu poser un essai de 60 jours : on le remplace.
insert into subscriptions (station_id, status)
select station_id, 'active' from demo_const
on conflict (station_id) do update
   set status = 'active', plan = null, trial_ends_at = null,
       current_period_end = null, suspended_at = null,
       stripe_customer_id = null, stripe_subscription_id = null;

-- ---------------------------------------------------------------------------
-- 2. Remise à zéro : tout ce qui appartient à la caserne, et elle seule
-- ---------------------------------------------------------------------------
alter table schedules disable trigger schedules_guard_suppression;
alter table shifts    disable trigger shifts_guard_suppression;
-- La suppression d'un mois laisse sinon une ligne d'audit par passage : ce
-- journal-là est celui des vraies casernes.
alter table periods   disable trigger periods_audit_suppression;

delete from notification_outbox where station_id = (select station_id from demo_const);
delete from notifications       where station_id = (select station_id from demo_const);
delete from assignments         where station_id = (select station_id from demo_const);
delete from shifts              where station_id = (select station_id from demo_const);
delete from schedules           where station_id = (select station_id from demo_const);
delete from availability_preferences where station_id = (select station_id from demo_const);
delete from availabilities      where station_id = (select station_id from demo_const);
delete from periods             where station_id = (select station_id from demo_const);
delete from invitations         where station_id = (select station_id from demo_const);
delete from memberships         where station_id = (select station_id from demo_const);
delete from audit_log           where station_id = (select station_id from demo_const);

alter table schedules enable trigger schedules_guard_suppression;
alter table shifts    enable trigger shifts_guard_suppression;
alter table periods   enable trigger periods_audit_suppression;

-- ---------------------------------------------------------------------------
-- 3. Les membres
-- ---------------------------------------------------------------------------
-- Le compte de revue : le seul qui se connecte. Créé sans mot de passe s'il
-- manque ; l'API d'administration Auth lui en pose un ensuite.
-- Les colonnes *_token doivent valoir '' (et non null) pour que GoTrue lise la ligne.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new, email_change_token_current
)
select '00000000-0000-0000-0000-000000000000', c.review_new_id, 'authenticated', 'authenticated',
       c.review_email, '', now(),
       '{"provider": "email", "providers": ["email"]}'::jsonb,
       '{"first_name": "Alex", "last_name": "Relecteur"}'::jsonb,
       now(), now(), '', '', '', '', ''
from demo_const c
where not exists (select 1 from auth.users u where lower(u.email) = c.review_email);

insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), u.id, u.id::text, 'email',
       jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
       null, now(), now()
from auth.users u, demo_const c
where lower(u.email) = c.review_email
  and not exists (select 1 from auth.identities i where i.user_id = u.id and i.provider = 'email');

-- Adresse confirmée : la connexion par mot de passe l'exige.
update auth.users u set email_confirmed_at = coalesce(u.email_confirmed_at, now())
from demo_const c where lower(u.email) = c.review_email;

-- L'équipe : ordinal 0 = le compte de revue, 1 = le chef (admin fictif), 2..9.
create temp table demo_team (
  ordinal      int primary key,
  user_id      uuid not null,
  email        text not null,
  first_name   text not null,
  last_name    text not null,
  role         membership_role not null,
  display_name text not null
) on commit drop;

insert into demo_team
select 0, u.id, c.review_email, 'Alex', 'Relecteur', 'member', 'Alex R.'
from auth.users u, demo_const c where lower(u.email) = c.review_email;

insert into demo_team (ordinal, user_id, email, first_name, last_name, role, display_name) values
  (1, 'de300000-0000-4000-8000-000000000110', 'chef@demo.astreinte-sp.invalid',     'Hélène',  'Marchand', 'admin',  'Hélène M.'),
  (2, 'de300000-0000-4000-8000-000000000111', 'membre1@demo.astreinte-sp.invalid',  'Yanis',   'Perrin',   'member', 'Yanis P.'),
  (3, 'de300000-0000-4000-8000-000000000112', 'membre2@demo.astreinte-sp.invalid',  'Inès',    'Collet',   'member', 'Inès C.'),
  (4, 'de300000-0000-4000-8000-000000000113', 'membre3@demo.astreinte-sp.invalid',  'Bastien', 'Renaud',   'member', 'Bastien R.'),
  (5, 'de300000-0000-4000-8000-000000000114', 'membre4@demo.astreinte-sp.invalid',  'Lina',    'Gauthier', 'member', 'Lina G.'),
  (6, 'de300000-0000-4000-8000-000000000115', 'membre5@demo.astreinte-sp.invalid',  'Mathis',  'Barbier',  'member', 'Mathis B.'),
  (7, 'de300000-0000-4000-8000-000000000116', 'membre6@demo.astreinte-sp.invalid',  'Clara',   'Arnaud',   'member', 'Clara A.'),
  (8, 'de300000-0000-4000-8000-000000000117', 'membre7@demo.astreinte-sp.invalid',  'Théo',    'Mercier',  'member', 'Théo M.'),
  (9, 'de300000-0000-4000-8000-000000000118', 'membre8@demo.astreinte-sp.invalid',  'Jade',    'Lemoine',  'member', 'Jade L.');

do $$
begin
  if not exists (select 1 from demo_team where ordinal = 0) then
    raise exception 'caserne_demo_compte_revue_absent';
  end if;
end $$;

-- Profils : le compte de revue a le sien (déclencheur handle_new_user) ; les
-- membres fictifs n'ont qu'un profil, sans compte d'authentification.
insert into profiles (id, email, first_name, last_name, phone, push_enabled, locale)
select t.user_id, t.email, t.first_name, t.last_name, null, true, 'fr'
from demo_team t
on conflict (id) do update
   set email = excluded.email, first_name = excluded.first_name,
       last_name = excluded.last_name, phone = null;

insert into memberships (station_id, user_id, role, status, display_name)
select c.station_id, t.user_id, t.role, 'active', t.display_name
from demo_team t, demo_const c;

-- ---------------------------------------------------------------------------
-- 4. Les mois : M (validé), M+1 (publié, propositions), M+2 (saisie ouverte)
-- ---------------------------------------------------------------------------
create temp table demo_months (
  offset_m  int primary key,
  period_id uuid not null,
  first_day date not null,
  last_day  date not null
) on commit drop;

insert into demo_months
select m,
       ('de300000-0000-4000-8000-00000000020' || m)::uuid,
       (date_trunc('month', now() at time zone 'Europe/Paris') + make_interval(months => m))::date,
       (date_trunc('month', now() at time zone 'Europe/Paris') + make_interval(months => m + 1) - interval '1 day')::date
from generate_series(0, 2) m;

insert into periods (id, station_id, year, month, status, deadline_at, locked_at)
select dm.period_id, c.station_id,
       extract(year from dm.first_day)::int, extract(month from dm.first_day)::int,
       case when dm.offset_m < 2 then 'locked' else 'open' end::period_status,
       case when dm.offset_m < 2
            then least(period_deadline_at(extract(year from dm.first_day)::int,
                                          extract(month from dm.first_day)::int, 15, 'Europe/Paris'),
                       now() - interval '1 hour')
            else period_deadline_at(extract(year from dm.first_day)::int,
                                    extract(month from dm.first_day)::int, 15, 'Europe/Paris')
       end,
       case when dm.offset_m < 2 then now() - interval '1 hour' end
from demo_months dm, demo_const c;

-- Plannings : insérés directement dans leur état (le garde-fou de transition ne
-- regarde que les mises à jour), sans passer par la publication, qui écrirait
-- des notifications à toute l'équipe fictive.
insert into schedules (id, station_id, period_id, status, published_at, validated_at, created_by)
select ('de300000-0000-4000-8000-00000000030' || dm.offset_m)::uuid, c.station_id, dm.period_id,
       case dm.offset_m when 0 then 'validated' else 'published' end::schedule_status,
       now() - make_interval(days => 20 - 10 * dm.offset_m),
       case dm.offset_m when 0 then now() - interval '9 days' end,
       c.chef_id
from demo_months dm, demo_const c
where dm.offset_m < 2;

insert into shifts (station_id, schedule_id, date, slot, required_count)
select c.station_id, ('de300000-0000-4000-8000-00000000030' || dm.offset_m)::uuid, d::date, s.slot, 2
from demo_months dm
cross join demo_const c
cross join generate_series(dm.first_day, dm.last_day, interval '1 day') d
cross join (values ('day'::slot_type), ('night'::slot_type)) s(slot)
where dm.offset_m < 2;

-- Attributions : deux personnes par créneau, en rotation sur les dix membres.
-- Le compte de revue revient environ tous les cinq créneaux.
create temp table demo_assign (
  shift_id uuid not null,
  date     date not null,
  slot     slot_type not null,
  offset_m int not null,
  user_id  uuid not null,
  ordinal  int not null,
  n        int not null
) on commit drop;

with numbered as (
  select sh.id as shift_id, sh.date, sh.slot, dm.offset_m,
         (row_number() over (order by sh.date, sh.slot))::int - 1 as i
  from shifts sh
  join demo_months dm on sh.date between dm.first_day and dm.last_day
  where sh.station_id = (select station_id from demo_const)
)
insert into demo_assign (shift_id, date, slot, offset_m, user_id, ordinal, n)
select nb.shift_id, nb.date, nb.slot, nb.offset_m, t.user_id, t.ordinal, nb.i
from numbered nb
cross join (values (0), (1)) k(k)
join demo_team t on t.ordinal = (2 * nb.i + k.k) % 10;

-- Disponibilités : chaque personne attribuée était disponible ; d'autres
-- créneaux au hasard (reproductible) pour remplir les grilles de M+1 et M+2.
do $$ begin perform setseed(0.76); end $$;

insert into availabilities (station_id, user_id, date, slot, status, set_by)
select (select station_id from demo_const), a.user_id, a.date, a.slot, 'available', a.user_id
from demo_assign a
on conflict (station_id, user_id, date, slot) do nothing;

insert into availabilities (station_id, user_id, date, slot, status, set_by)
select (select station_id from demo_const), t.user_id, d::date, s.slot,
       case when random() < 0.8 then 'available' else 'absent' end::availability_status,
       t.user_id
from demo_months dm
cross join generate_series(dm.first_day, dm.last_day, interval '1 day') d
cross join (values ('day'::slot_type), ('night'::slot_type)) s(slot)
cross join demo_team t
where dm.offset_m in (1, 2)
  and t.ordinal > 0           -- le compte de revue saisit M+2 lui-même
  and random() < 0.45
on conflict (station_id, user_id, date, slot) do nothing;

-- M : tout accepté. M+1 : le compte de revue a tout « proposé » ; les autres
-- ont répondu pour les deux tiers.
insert into assignments (station_id, shift_id, user_id, status, was_available,
                         proposed_at, responded_at, created_by)
select c.station_id, a.shift_id, a.user_id,
       case
         when a.offset_m = 0 then 'accepted'
         when a.ordinal = 0 then 'proposed'
         when a.n % 3 = 0 then 'proposed'
         else 'accepted'
       end::assignment_status,
       true,
       now() - make_interval(days => 20 - 10 * a.offset_m),
       case
         when a.offset_m = 0 then now() - interval '15 days'
         when a.ordinal = 0 or a.n % 3 = 0 then null
         else now() - interval '2 days'
       end,
       c.chef_id
from demo_assign a, demo_const c;

-- ---------------------------------------------------------------------------
-- 5. Le centre de notifications du compte de revue
-- ---------------------------------------------------------------------------
insert into notifications (station_id, user_id, type, channel, title, body, data, sent_at, read_at, created_at)
select c.station_id, t.user_id, 'assignment_proposed'::notification_type, 'inapp'::notification_channel,
       format('%s astreintes proposées', (select count(*) from demo_assign a where a.offset_m = 1 and a.ordinal = 0)),
       'CIS Démonstration te propose des astreintes pour le mois prochain. Accepte ou refuse chacune depuis l''application.',
       '{"route": "/proposals"}'::jsonb,
       now() - interval '10 days', null, now() - interval '10 days'
from demo_team t, demo_const c where t.ordinal = 0
union all
select c.station_id, t.user_id, 'schedule_validated'::notification_type, 'inapp'::notification_channel,
       'Planning du mois validé',
       'Le planning de CIS Démonstration est complet : toutes les astreintes du mois sont acceptées.',
       jsonb_build_object('route', '/schedule/' || to_char((select first_day from demo_months where offset_m = 0), 'YYYY-MM')),
       now() - interval '9 days', now() - interval '8 days', now() - interval '9 days'
from demo_team t, demo_const c where t.ordinal = 0;

-- ---------------------------------------------------------------------------
-- 6. Bilan
-- ---------------------------------------------------------------------------
select s.name,
       sub.status                                                      as abonnement,
       (select count(*) from memberships m where m.station_id = s.id)  as membres,
       (select string_agg(p.year || '-' || lpad(p.month::text, 2, '0') || ' ' || p.status, ', ' order by p.year, p.month)
          from periods p where p.station_id = s.id)                    as mois,
       (select count(*) from assignments a where a.station_id = s.id)  as attributions,
       (select count(*) from assignments a join demo_team t on t.user_id = a.user_id and t.ordinal = 0
         where a.station_id = s.id and a.status = 'proposed')          as propositions_revue
from stations s
join subscriptions sub on sub.station_id = s.id
where s.id = (select station_id from demo_const);

commit;
