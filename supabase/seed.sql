-- Seed de développement — Astreinte SP.
-- Rejoué par `supabase db reset` après les migrations. Réutilisé par les tests Flutter :
-- les identifiants ci-dessous sont fixes et documentés dans supabase/README.md.
--
-- Contenu :
--   - 2 casernes (A : CIS Saint-Martin, B : CIS Val-de-Loue), en essai (`trialing`).
--   - Par caserne : 1 admin + 8 membres dans auth.users (le trigger handle_new_user crée
--     les profils), memberships actives.
--   - Périodes M+1 et M+2 calculées depuis now(), deadline le 15 du mois précédent à
--     23:59:59 dans le fuseau de la caserne. M+1 est `locked` si sa deadline est passée.
--   - Disponibilités pseudo-aléatoires mais reproductibles (setseed), saisies par le
--     membre lui-même (set_by = user_id).
--   - Préférences de quotas pour la moitié des membres (membre1 à membre4).
--   - Aucun planning ni attribution (ticket 017).
--
-- Mot de passe de tous les comptes : astreinte-dev
-- Emails : admin@caserne-a.test, membre1@caserne-a.test … membre8@caserne-b.test

begin;

select setseed(0.42);

-- ---------------------------------------------------------------------------
-- Casernes
-- ---------------------------------------------------------------------------
insert into stations (id, name, slug, timezone) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'CIS Saint-Martin', 'saint-martin', 'Europe/Paris'),
  ('bbbbbbbb-0000-4000-8000-000000000001', 'CIS Val-de-Loue',  'val-de-loue',  'Europe/Paris');

-- ---------------------------------------------------------------------------
-- Utilisateurs (auth.users + auth.identities) et memberships
-- ---------------------------------------------------------------------------
create temp table seed_users (
  id           uuid primary key,
  station_id   uuid not null,
  email        text not null,
  first_name   text not null,
  last_name    text not null,
  role         membership_role not null,
  display_name text not null,
  ordinal      int not null            -- 0 = admin, 1..8 = membreN
) on commit drop;

insert into seed_users (id, station_id, email, first_name, last_name, role, display_name, ordinal) values
  -- Caserne A
  ('aaaaaaaa-0000-4000-8000-000000000100', 'aaaaaaaa-0000-4000-8000-000000000001', 'admin@caserne-a.test',   'Jean',     'Dupont',    'admin',  'Jean D.',     0),
  ('aaaaaaaa-0000-4000-8000-000000000101', 'aaaaaaaa-0000-4000-8000-000000000001', 'membre1@caserne-a.test', 'Marie',    'Lefebvre',  'member', 'Marie L.',    1),
  ('aaaaaaaa-0000-4000-8000-000000000102', 'aaaaaaaa-0000-4000-8000-000000000001', 'membre2@caserne-a.test', 'Thomas',   'Moreau',    'member', 'Thomas M.',   2),
  ('aaaaaaaa-0000-4000-8000-000000000103', 'aaaaaaaa-0000-4000-8000-000000000001', 'membre3@caserne-a.test', 'Camille',  'Girard',    'member', 'Camille G.',  3),
  ('aaaaaaaa-0000-4000-8000-000000000104', 'aaaaaaaa-0000-4000-8000-000000000001', 'membre4@caserne-a.test', 'Lucas',    'Bernard',   'member', 'Lucas B.',    4),
  ('aaaaaaaa-0000-4000-8000-000000000105', 'aaaaaaaa-0000-4000-8000-000000000001', 'membre5@caserne-a.test', 'Émilie',   'Roux',      'member', 'Émilie R.',   5),
  ('aaaaaaaa-0000-4000-8000-000000000106', 'aaaaaaaa-0000-4000-8000-000000000001', 'membre6@caserne-a.test', 'Nicolas',  'Fontaine',  'member', 'Nicolas F.',  6),
  ('aaaaaaaa-0000-4000-8000-000000000107', 'aaaaaaaa-0000-4000-8000-000000000001', 'membre7@caserne-a.test', 'Sophie',   'Garnier',   'member', 'Sophie G.',   7),
  ('aaaaaaaa-0000-4000-8000-000000000108', 'aaaaaaaa-0000-4000-8000-000000000001', 'membre8@caserne-a.test', 'Antoine',  'Chevalier', 'member', 'Antoine C.',  8),
  -- Caserne B
  ('bbbbbbbb-0000-4000-8000-000000000100', 'bbbbbbbb-0000-4000-8000-000000000001', 'admin@caserne-b.test',   'Claire',   'Martin',    'admin',  'Claire M.',   0),
  ('bbbbbbbb-0000-4000-8000-000000000101', 'bbbbbbbb-0000-4000-8000-000000000001', 'membre1@caserne-b.test', 'Julien',   'Petit',     'member', 'Julien P.',   1),
  ('bbbbbbbb-0000-4000-8000-000000000102', 'bbbbbbbb-0000-4000-8000-000000000001', 'membre2@caserne-b.test', 'Laura',    'Simon',     'member', 'Laura S.',    2),
  ('bbbbbbbb-0000-4000-8000-000000000103', 'bbbbbbbb-0000-4000-8000-000000000001', 'membre3@caserne-b.test', 'Maxime',   'Laurent',   'member', 'Maxime L.',   3),
  ('bbbbbbbb-0000-4000-8000-000000000104', 'bbbbbbbb-0000-4000-8000-000000000001', 'membre4@caserne-b.test', 'Pauline',  'Michel',    'member', 'Pauline M.',  4),
  ('bbbbbbbb-0000-4000-8000-000000000105', 'bbbbbbbb-0000-4000-8000-000000000001', 'membre5@caserne-b.test', 'Hugo',     'Lambert',   'member', 'Hugo L.',     5),
  ('bbbbbbbb-0000-4000-8000-000000000106', 'bbbbbbbb-0000-4000-8000-000000000001', 'membre6@caserne-b.test', 'Manon',    'Rousseau',  'member', 'Manon R.',    6),
  ('bbbbbbbb-0000-4000-8000-000000000107', 'bbbbbbbb-0000-4000-8000-000000000001', 'membre7@caserne-b.test', 'Kevin',    'Faure',     'member', 'Kevin F.',    7),
  ('bbbbbbbb-0000-4000-8000-000000000108', 'bbbbbbbb-0000-4000-8000-000000000001', 'membre8@caserne-b.test', 'Chloé',    'Blanc',     'member', 'Chloé B.',    8);

-- auth.users : le trigger on_auth_user_created crée la ligne profiles.
-- Les colonnes *_token doivent valoir '' (et non null) pour que GoTrue lise la ligne.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new, email_change_token_current
)
select
  '00000000-0000-0000-0000-000000000000',
  u.id,
  'authenticated',
  'authenticated',
  u.email,
  extensions.crypt('astreinte-dev', extensions.gen_salt('bf')),
  now(),
  '{"provider": "email", "providers": ["email"]}'::jsonb,
  jsonb_build_object('first_name', u.first_name, 'last_name', u.last_name),
  now(),
  now(),
  '', '', '', '', ''
from seed_users u
order by u.station_id, u.ordinal;

insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
select
  gen_random_uuid(),
  u.id,
  u.id::text,
  'email',
  jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
  now(),
  now(),
  now()
from seed_users u
order by u.station_id, u.ordinal;

-- Téléphones fictifs sur quelques profils pour tester l'affichage.
update profiles p
set phone = '+3360000' || lpad((u.ordinal + case when u.station_id::text like 'aaaa%' then 100 else 200 end)::text, 4, '0')
from seed_users u
where u.id = p.id and u.ordinal in (0, 1, 2, 5);

insert into memberships (station_id, user_id, role, status, display_name)
select u.station_id, u.id, u.role, 'active', u.display_name
from seed_users u
order by u.station_id, u.ordinal;

-- ---------------------------------------------------------------------------
-- Périodes M+1 et M+2 par caserne
-- deadline_at = jour settings.availability_deadline_day du mois précédent, 23:59:59,
-- dans le fuseau de la caserne. Verrouillée si la deadline est déjà passée.
-- ---------------------------------------------------------------------------
create temp table seed_periods (
  id         uuid primary key,
  station_id uuid not null,
  first_day  date not null
) on commit drop;

insert into seed_periods (id, station_id, first_day) values
  ('aaaaaaaa-0000-4000-8000-000000000201', 'aaaaaaaa-0000-4000-8000-000000000001', (date_trunc('month', now()) + interval '1 month')::date),
  ('aaaaaaaa-0000-4000-8000-000000000202', 'aaaaaaaa-0000-4000-8000-000000000001', (date_trunc('month', now()) + interval '2 months')::date),
  ('bbbbbbbb-0000-4000-8000-000000000201', 'bbbbbbbb-0000-4000-8000-000000000001', (date_trunc('month', now()) + interval '1 month')::date),
  ('bbbbbbbb-0000-4000-8000-000000000202', 'bbbbbbbb-0000-4000-8000-000000000001', (date_trunc('month', now()) + interval '2 months')::date);

insert into periods (id, station_id, year, month, status, deadline_at, locked_at)
select
  p.id,
  p.station_id,
  extract(year from p.first_day)::int,
  extract(month from p.first_day)::int,
  case when d.deadline_at < now() then 'locked' else 'open' end::period_status,
  d.deadline_at,
  case when d.deadline_at < now() then d.deadline_at else null end
from seed_periods p
join stations s on s.id = p.station_id
cross join lateral (
  -- Même règle que le cron de création et que le recalcul des dates limites :
  -- une seule écriture, dans period_deadline_at (migration 0011).
  select period_deadline_at(
    extract(year  from p.first_day)::int,
    extract(month from p.first_day)::int,
    (s.settings ->> 'availability_deadline_day')::int,
    s.timezone
  ) as deadline_at
) d
order by p.station_id, p.first_day;

-- ---------------------------------------------------------------------------
-- Disponibilités pseudo-aléatoires (reproductibles grâce à setseed ci-dessus).
-- Boucle plpgsql à ordre d'itération fixe pour que la suite random() soit
-- consommée dans le même ordre à chaque reset.
--   r < 0.50 : available ; 0.50 <= r < 0.60 : absent ; sinon non saisi.
-- ---------------------------------------------------------------------------
do $$
declare
  m   record;
  p   record;
  d   date;
  sl  slot_type;
  r   double precision;
begin
  for m in
    select ms.station_id, ms.user_id
    from memberships ms
    join seed_users u on u.id = ms.user_id
    order by ms.station_id, u.ordinal
  loop
    for p in
      select sp.first_day
      from seed_periods sp
      where sp.station_id = m.station_id
      order by sp.first_day
    loop
      d := p.first_day;
      while d < p.first_day + interval '1 month' loop
        foreach sl in array array['day', 'night']::slot_type[] loop
          r := random();
          if r < 0.50 then
            insert into availabilities (station_id, user_id, date, slot, status, set_by)
            values (m.station_id, m.user_id, d, sl, 'available', m.user_id);
          elsif r < 0.60 then
            insert into availabilities (station_id, user_id, date, slot, status, set_by)
            values (m.station_id, m.user_id, d, sl, 'absent', m.user_id);
          end if;
        end loop;
        d := d + 1;
      end loop;
    end loop;
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- Préférences de quotas pour la moitié des membres (membre1 à membre4), sur les
-- deux périodes.
-- ---------------------------------------------------------------------------
insert into availability_preferences (station_id, user_id, period_id, max_shifts, max_weekends, comment)
select
  u.station_id,
  u.id,
  sp.id,
  case u.ordinal when 1 then 4 when 2 then 6 when 3 then null when 4 then 8 end,
  case u.ordinal when 1 then 1 when 2 then 2 when 3 then 1 when 4 then null end,
  case u.ordinal
    when 1 then 'Pas plus d''un weekend, garde des enfants.'
    when 2 then null
    when 3 then 'Nuits de préférence.'
    when 4 then 'Disponible surtout en semaine.'
  end
from seed_users u
join seed_periods sp on sp.station_id = u.station_id
where u.ordinal between 1 and 4
order by u.station_id, u.ordinal, sp.first_day;

-- ---------------------------------------------------------------------------
-- Abonnements : période d'essai de 30 jours par caserne.
-- ---------------------------------------------------------------------------
insert into subscriptions (station_id, status, trial_ends_at) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'trialing', now() + interval '30 days'),
  ('bbbbbbbb-0000-4000-8000-000000000001', 'trialing', now() + interval '30 days');

commit;
