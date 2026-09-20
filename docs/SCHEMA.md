# Schéma de base de données — Supabase

Un seul projet Supabase pour toutes les casernes. Chaque table métier porte un `station_id`
et est protégée par Row Level Security. Ce document est la référence : la première migration
(ticket 002) doit le reproduire fidèlement.

Conventions :
- `uuid` en clé primaire, `gen_random_uuid()`.
- `created_at` et `updated_at` en `timestamptz`, mis à jour par trigger.
- Enums Postgres pour les statuts.
- Les dates d'astreinte sont des `date` (pas de timestamp) : un créneau est « le 12 octobre,
  nuit », le fuseau de la caserne sert uniquement à l'affichage et aux crons.

---

## 1. Enums

```sql
create type membership_role as enum ('member', 'admin');
create type membership_status as enum ('invited', 'active', 'disabled');
create type slot_type as enum ('day', 'night');
create type availability_status as enum ('available', 'absent');
create type period_status as enum ('open', 'locked');
create type schedule_status as enum ('draft', 'published', 'validated', 'archived');
create type assignment_status as enum ('proposed', 'accepted', 'declined', 'replaced', 'cancelled');
create type push_platform as enum ('ios', 'android', 'web');
create type notification_channel as enum ('push', 'email', 'inapp');
create type notification_type as enum (
  'invitation',
  'availability_reminder',
  'assignment_proposed',
  'assignment_reminder',
  'assignment_declined',
  'assignment_changed',
  'assignment_cancelled',
  'schedule_validated',
  'schedule_all_accepted',
  'late_responders'
);
create type subscription_status as enum ('trialing', 'active', 'past_due', 'suspended', 'cancelled');
```

## 2. Tables

### 2.1 `stations` — casernes

```sql
create table stations (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  slug          text not null unique,
  timezone      text not null default 'Europe/Paris',
  settings      jsonb not null default '{
    "day_start": "07:00",
    "day_end": "19:00",
    "required_day": 1,
    "required_night": 1,
    "availability_deadline_day": 15,
    "response_reminder_hours": 24,
    "response_email_hours": 48,
    "late_report_hours": 72
  }'::jsonb,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
```

`settings` est validé côté Edge Function et côté app. Clés :
- `day_start`, `day_end` : affichage uniquement.
- `required_day`, `required_night` : effectif par défaut d'un créneau.
- `required_overrides` (optionnel) : `{"sat": {"day": 2}, "2026-12-31": {"night": 3}}`.
- `availability_deadline_day` : jour du mois précédent où la saisie se verrouille.
- Délais de relance en heures.

### 2.2 `profiles` — extension de `auth.users`

```sql
create table profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  first_name    text not null default '',
  last_name     text not null default '',
  email         text not null,
  phone         text,
  push_enabled  boolean not null default true,
  locale        text not null default 'fr',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
```

Créé par trigger sur `auth.users` à l'inscription. `email` est dupliqué pour les jointures
sans toucher au schéma `auth`.

### 2.3 `memberships` — appartenance à une caserne

```sql
create table memberships (
  id            uuid primary key default gen_random_uuid(),
  station_id    uuid not null references stations(id) on delete cascade,
  user_id       uuid not null references profiles(id) on delete cascade,
  role          membership_role not null default 'member',
  status        membership_status not null default 'active',
  display_name  text,                -- surnom ou nom court affiché dans la caserne
  skills        text[] not null default '{}',  -- réservé v1.1 (chef d'agrès, conducteur...)
  joined_at     timestamptz not null default now(),
  disabled_at   timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (station_id, user_id)
);
create index on memberships (user_id);
create index on memberships (station_id, status);
```

### 2.4 `invitations`

```sql
create table invitations (
  id            uuid primary key default gen_random_uuid(),
  station_id    uuid not null references stations(id) on delete cascade,
  email         text not null,
  role          membership_role not null default 'member',
  token         text not null unique default encode(gen_random_bytes(24), 'hex'),
  invited_by    uuid not null references profiles(id),
  expires_at    timestamptz not null default now() + interval '14 days',
  accepted_at   timestamptz,
  created_at    timestamptz not null default now()
);
create unique index invitations_pending_uniq
  on invitations (station_id, lower(email)) where accepted_at is null;
```

### 2.5 `periods` — un mois de saisie par caserne

```sql
create table periods (
  id            uuid primary key default gen_random_uuid(),
  station_id    uuid not null references stations(id) on delete cascade,
  year          int not null,
  month         int not null check (month between 1 and 12),
  status        period_status not null default 'open',
  deadline_at   timestamptz not null,
  locked_at     timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (station_id, year, month)
);
```

Créée automatiquement (cron mensuel ou à la demande) pour M+1 et M+2. `deadline_at` est
calculée depuis `settings.availability_deadline_day` dans le fuseau de la caserne.

### 2.6 `availabilities`

```sql
create table availabilities (
  id            uuid primary key default gen_random_uuid(),
  station_id    uuid not null references stations(id) on delete cascade,
  user_id       uuid not null references profiles(id) on delete cascade,
  date          date not null,
  slot          slot_type not null,
  status        availability_status not null default 'available',
  set_by        uuid references profiles(id),  -- différent de user_id si saisi par un admin
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (station_id, user_id, date, slot)
);
create index on availabilities (station_id, date);
create index on availabilities (user_id, date);
```

Absence de ligne = non saisi. L'app écrit par upsert et supprime pour « décocher ».

### 2.7 `availability_preferences` — quotas par membre et par mois

```sql
create table availability_preferences (
  id            uuid primary key default gen_random_uuid(),
  station_id    uuid not null references stations(id) on delete cascade,
  user_id       uuid not null references profiles(id) on delete cascade,
  period_id     uuid not null references periods(id) on delete cascade,
  max_shifts    int check (max_shifts is null or max_shifts >= 0),   -- null = illimité
  max_weekends  int check (max_weekends is null or max_weekends >= 0), -- null = illimité
  comment       text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (station_id, user_id, period_id)
);
```

### 2.8 `schedules` — un planning par caserne et par mois

```sql
create table schedules (
  id            uuid primary key default gen_random_uuid(),
  station_id    uuid not null references stations(id) on delete cascade,
  period_id     uuid not null references periods(id) on delete cascade,
  status        schedule_status not null default 'draft',
  published_at  timestamptz,
  validated_at  timestamptz,
  created_by    uuid not null references profiles(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (station_id, period_id)
);
```

### 2.9 `shifts` — créneaux à pourvoir

```sql
create table shifts (
  id              uuid primary key default gen_random_uuid(),
  station_id      uuid not null references stations(id) on delete cascade,
  schedule_id     uuid not null references schedules(id) on delete cascade,
  date            date not null,
  slot            slot_type not null,
  required_count  int not null default 1 check (required_count >= 0),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (schedule_id, date, slot)
);
create index on shifts (station_id, date);
```

Générés à la création du planning (tous les jours du mois × 2 créneaux) avec
`required_count` déduit des settings. L'admin peut modifier `required_count` par créneau.

### 2.10 `assignments` — attribution d'un membre à un créneau

```sql
create table assignments (
  id              uuid primary key default gen_random_uuid(),
  station_id      uuid not null references stations(id) on delete cascade,
  shift_id        uuid not null references shifts(id) on delete cascade,
  user_id         uuid not null references profiles(id) on delete cascade,
  status          assignment_status not null default 'proposed',
  was_available   boolean not null default true,  -- false si attribué hors disponibilité
  proposed_at     timestamptz,                    -- renseigné à la publication
  responded_at    timestamptz,
  decline_reason  text,
  replaced_by     uuid references assignments(id),
  reminder_count  int not null default 0,
  last_reminder_at timestamptz,
  created_by      uuid not null references profiles(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create unique index assignments_active_uniq
  on assignments (shift_id, user_id)
  where status in ('proposed', 'accepted');
create index on assignments (user_id, status);
create index on assignments (station_id, status);
```

Un membre ne peut avoir qu'une attribution active par créneau. Les attributions
`declined`, `replaced`, `cancelled` restent pour l'historique.

### 2.11 `push_tokens`

```sql
create table push_tokens (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles(id) on delete cascade,
  token         text not null unique,
  platform      push_platform not null,
  device_label  text,
  last_seen_at  timestamptz not null default now(),
  created_at    timestamptz not null default now()
);
create index on push_tokens (user_id);
```

Un token invalide renvoyé par FCM est supprimé par l'Edge Function d'envoi.

### 2.12 `notifications` — journal et centre de notifications

```sql
create table notifications (
  id            uuid primary key default gen_random_uuid(),
  station_id    uuid references stations(id) on delete cascade,
  user_id       uuid not null references profiles(id) on delete cascade,
  type          notification_type not null,
  channel       notification_channel not null,
  title         text not null,
  body          text not null,
  data          jsonb not null default '{}'::jsonb,  -- deep link : {"route": "/proposals", "assignment_id": "..."}
  sent_at       timestamptz,
  delivered     boolean,
  read_at       timestamptz,
  error         text,
  created_at    timestamptz not null default now()
);
create index on notifications (user_id, created_at desc);
create index on notifications (user_id) where read_at is null;
```

Une ligne `inapp` par événement alimente le centre de notifications. Les lignes `push`
et `email` tracent les envois.

### 2.13 `subscriptions`

```sql
create table subscriptions (
  station_id              uuid primary key references stations(id) on delete cascade,
  status                  subscription_status not null default 'trialing',
  stripe_customer_id      text unique,
  stripe_subscription_id  text unique,
  plan                    text,                 -- 'monthly' | 'yearly'
  trial_ends_at           timestamptz,
  current_period_end      timestamptz,
  suspended_at            timestamptz,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);
```

### 2.14 `audit_log`

```sql
create table audit_log (
  id            bigint generated always as identity primary key,
  station_id    uuid references stations(id) on delete cascade,
  actor_id      uuid references profiles(id),
  action        text not null,      -- 'availability.set_for_member', 'period.reopen', 'assignment.force', ...
  entity        text not null,
  entity_id     uuid,
  data          jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now()
);
create index on audit_log (station_id, created_at desc);
```

### 2.15 `super_admins`

```sql
create table super_admins (
  user_id       uuid primary key references profiles(id) on delete cascade,
  created_at    timestamptz not null default now()
);
```

## 3. Fonctions utilitaires (SQL, `security definer`)

```sql
-- Vrai si l'utilisateur courant est membre actif de la caserne.
create function is_member(p_station uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from memberships
    where station_id = p_station and user_id = auth.uid() and status = 'active'
  );
$$;

-- Vrai si l'utilisateur courant est admin actif de la caserne.
create function is_admin(p_station uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from memberships
    where station_id = p_station and user_id = auth.uid()
      and status = 'active' and role = 'admin'
  );
$$;

create function is_super_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from super_admins where user_id = auth.uid());
$$;

-- Vrai si la caserne n'est pas suspendue (écriture autorisée).
create function station_writable(p_station uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select status in ('trialing', 'active', 'past_due') from subscriptions where station_id = p_station),
    true
  );
$$;
```

## 4. Row Level Security

RLS activé sur toutes les tables. Principes :

| Table | Lecture | Écriture |
|---|---|---|
| `stations` | membre de la caserne ou super-admin | admin de la caserne (update), super-admin (insert) |
| `profiles` | soi-même, et les profils des membres de ses casernes | soi-même |
| `memberships` | membre de la caserne | admin de la caserne, sauf son propre rôle |
| `invitations` | admin de la caserne | admin de la caserne |
| `periods` | membre | admin |
| `availabilities` | membre : les siennes ; admin : toutes celles de la caserne | membre : les siennes si période `open` et caserne writable ; admin : toutes |
| `availability_preferences` | idem availabilities | idem |
| `schedules` | membre si `status <> 'draft'` ; admin toujours | admin |
| `shifts` | membre si le schedule est publié ou validé ; admin toujours | admin |
| `assignments` | membre : les siennes si schedule publié ; tous les membres si validé ; admin toutes | membre : `status` uniquement, de `proposed` vers `accepted` ou `declined`, sur les siennes ; admin : tout |
| `push_tokens` | soi-même | soi-même |
| `notifications` | soi-même | soi-même (`read_at` uniquement) ; insert par service role |
| `subscriptions` | admin de la caserne | service role uniquement (webhook Stripe) |
| `audit_log` | admin de la caserne | service role et triggers |
| `super_admins` | super-admin | personne (SQL manuel) |

Exemple de politique pour `availabilities` :

```sql
alter table availabilities enable row level security;

create policy "member reads own, admin reads all"
  on availabilities for select
  using (user_id = auth.uid() or is_admin(station_id));

create policy "member writes own during open period"
  on availabilities for insert
  with check (
    user_id = auth.uid()
    and is_member(station_id)
    and station_writable(station_id)
    and exists (
      select 1 from periods p
      where p.station_id = availabilities.station_id
        and p.year = extract(year from availabilities.date)
        and p.month = extract(month from availabilities.date)
        and p.status = 'open'
    )
  );
-- update et delete : même condition. Politique admin séparée sans condition de période.
```

La transition de statut d'une attribution par un membre est verrouillée par trigger :

```sql
create function assignments_member_transition() returns trigger
language plpgsql as $$
begin
  if is_admin(new.station_id) then return new; end if;
  if old.user_id <> auth.uid() then raise exception 'forbidden'; end if;
  if old.status <> 'proposed' or new.status not in ('accepted', 'declined') then
    raise exception 'invalid transition';
  end if;
  -- un membre ne modifie rien d'autre que status, responded_at, decline_reason
  if new.shift_id <> old.shift_id or new.user_id <> old.user_id then
    raise exception 'forbidden';
  end if;
  new.responded_at := now();
  return new;
end $$;
```

## 5. Triggers

- `set_updated_at` sur toutes les tables avec `updated_at`.
- `handle_new_user` sur `auth.users` : crée la ligne `profiles`.
- `assignments_member_transition` (ci-dessus).
- `schedule_auto_validate` : après update d'un `assignment`, si tous les créneaux du
  planning ont `count(accepted) >= required_count`, passe le planning en `validated` et
  insère une notification `schedule_validated` (via `pg_net` vers l'Edge Function, ou via
  une table `outbox` lue par cron — choix ticket 025).
- `audit_admin_actions` : sur `availabilities` quand `set_by <> user_id`, sur `periods`
  quand `status` passe de `locked` à `open`, sur `assignments` quand `was_available = false`.

## 6. Vues

### `v_availability_matrix` — matrice admin d'un mois

Une ligne par (membre actif, date, créneau) du mois, avec le statut de disponibilité
(`available`, `absent`, `null` = non saisi), et les préférences du membre.
Paramétrée via une fonction `availability_matrix(p_station uuid, p_period uuid)`
plutôt qu'une vue pour porter les filtres.

### `v_member_load` — charge d'un membre

Par (station, user, period) : nombre d'astreintes acceptées ou proposées, nombre de
weekends distincts couverts, quotas déclarés, quotas restants, et nombre d'astreintes
acceptées sur les 3 périodes précédentes (pour l'équilibrage).

### `v_schedule_progress` — avancement d'un planning

Par schedule : créneaux totaux, créneaux pourvus, attributions en attente, acceptées,
refusées, retardataires (proposées depuis plus de `late_report_hours`).

## 7. Edge Functions

| Fonction | Déclencheur | Rôle |
|---|---|---|
| `send-notification` | appel interne (pg_net, cron, autres functions) | Prend un `notification_type`, un `user_id`, un payload ; écrit `notifications`, envoie push FCM et/ou email Resend selon les préférences et le fallback |
| `publish-schedule` | app admin | Passe le planning en `published`, renseigne `proposed_at`, déclenche les notifications groupées |
| `reassign-shift` | app admin | Marque l'ancienne attribution `replaced`, crée la nouvelle, notifie le nouveau membre et l'admin |
| `auto-propose` | app admin | Heuristique de remplissage du brouillon |
| `invite-member` | app admin | Crée l'invitation et envoie l'email |
| `accept-invitation` | app, après login | Vérifie le token, crée la membership |
| `stripe-webhook` | Stripe | Met à jour `subscriptions` |
| `create-checkout` | app admin | Crée une session Stripe Checkout |
| `ics-feed` | GET public avec token par membre | Génère le flux calendrier des astreintes acceptées |
| `export-user-data` | app | Export RGPD en JSON |

## 8. Tâches planifiées (pg_cron)

| Nom | Fréquence | Action |
|---|---|---|
| `create_periods` | 1er du mois, 02:00 | Crée les périodes M+1 et M+2 manquantes pour chaque caserne |
| `lock_periods` | toutes les heures | Passe en `locked` les périodes dont `deadline_at < now()` |
| `availability_reminders` | tous les jours 09:00 | Push J-3 et email J-1 aux membres sans saisie |
| `assignment_reminders` | toutes les heures | Rappel push à `response_reminder_hours`, email à `response_email_hours` |
| `late_responders_report` | toutes les heures | Notifie les admins des attributions en attente depuis `late_report_hours` |
| `archive_schedules` | 1er du mois | Archive les plannings des mois passés |
| `prune_notifications` | hebdomadaire | Supprime les notifications lues de plus de 90 jours |

## 9. Index et performance

Les index listés dans les DDL couvrent :
- la grille d'un membre : `availabilities (user_id, date)`,
- la matrice admin : `availabilities (station_id, date)` et `shifts (station_id, date)`,
- l'écran propositions : `assignments (user_id, status)`,
- le centre de notifications : `notifications (user_id) where read_at is null`.

Realtime activé sur `assignments`, `schedules`, `notifications` uniquement, filtré par
`station_id` côté client.

## 10. Migrations

Ordre proposé :
1. `0001_enums_and_stations.sql`
2. `0002_profiles_memberships_invitations.sql`
3. `0003_periods_availabilities_preferences.sql`
4. `0004_schedules_shifts_assignments.sql`
5. `0005_notifications_push_tokens.sql`
6. `0006_subscriptions_audit_super_admins.sql`
7. `0007_functions_rls.sql`
8. `0008_views.sql`
9. `0009_cron.sql`

Chaque migration est rejouable sur un projet vide et testée en local avec `supabase start`.
