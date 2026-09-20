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

`settings` est validé **en base** par la contrainte `stations_settings_valide`, appuyée sur
`station_settings_valid(jsonb)` (migration `0011`, ticket 010), et à l'identique côté
application (`lib/features/parametres/domain/validation_parametres.dart`). La validation
côté app donne la phrase avant l'envoi ; la contrainte est ce qui rend la règle vraie.

Clés, types et bornes — **la liste est une liste blanche, une clé inconnue est refusée** :

| Clé | Type | Bornes | Rôle |
|---|---|---|---|
| `day_start`, `day_end` | `"HH:MM"` | 00:00–23:59, et différentes l'une de l'autre | affichage uniquement |
| `required_day`, `required_night` | entier | 0–50 | effectif par défaut d'un créneau |
| `required_overrides` | objet, **optionnel** | voir ci-dessous | exceptions à l'effectif |
| `availability_deadline_day` | entier | 1–28 (le jour doit exister en février) | jour du mois précédent où la saisie se verrouille |
| `response_reminder_hours`, `response_email_hours`, `late_report_hours` | entier | 1–336 (deux semaines) | délais de relance, en heures |

`required_overrides` : `{"sat": {"day": 2}, "2026-12-31": {"night": 3}}`. Les clés sont soit
`mon`…`sun`, soit une date ISO **réelle** (le 30 février est refusé) ; les valeurs sont des
objets non vides dont les seules sous-clés sont `day` et `night`, entiers 0–50.

Deux garde-fous complètent la table :
- `stations_name_non_vide` : nom non blanc, 80 caractères au maximum.
- `stations_check_timezone` (trigger) : le fuseau doit exister dans `pg_timezone_names`.
  Un fuseau inventé n'échouerait sinon qu'au premier `make_timestamptz`, dans le cron.

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
calculée depuis `settings.availability_deadline_day` dans le fuseau de la caserne, par
`period_deadline_at(year, month, jour_limite, fuseau)` (migration `0011`) : le jour limite du
mois **précédent**, à 23:59:59.

**La date limite suit le réglage.** Quand un admin change `availability_deadline_day` ou le
fuseau de sa caserne, le déclencheur `stations_recalcule_deadlines` réécrit `deadline_at` des
périodes **encore `open`** (§ 5). Les périodes `locked` ne bougent pas : elles ont déjà produit
leur planning, et leur réécrire leur date limite réécrirait l'histoire.

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

**`required_count` est une copie, pas une référence.** Les settings de la caserne sont lus une
fois, à la création du planning ; ensuite, chaque créneau porte son propre effectif. Changer
`required_day` ou `required_night` ne touche donc **aucun créneau déjà créé** — c'est le critère
du ticket 010, et rien dans la base ne réécrit cette colonne
(`supabase/tests/station_settings_test.sql § 6`).

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

`pg_temp` est **nommé explicitement et en dernier** dans le `search_path` de toutes les
fonctions. Omis, PostgreSQL le consulte en premier : un rôle `authenticated` crée
`pg_temp.memberships`, y insère une ligne `admin` et `is_admin()` lui répond `true` pour
n'importe quelle caserne. La faille a été trouvée en revue du ticket 008 et corrigée par la
migration `0008`.

Les expressions des politiques RLS, elles, sont analysées à la création et stockées avec
les OID résolus, comme une vue : elles ne sont pas sensibles au `search_path` de l'appelant.

```sql
-- Vrai si l'utilisateur courant est membre actif de la caserne.
create function is_member(p_station uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from memberships
    where station_id = p_station and user_id = auth.uid() and status = 'active'
  );
$$;

-- Vrai si l'utilisateur courant est admin actif de la caserne.
create function is_admin(p_station uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from memberships
    where station_id = p_station and user_id = auth.uid()
      and status = 'active' and role = 'admin'
  );
$$;

create function is_super_admin() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from super_admins where user_id = auth.uid());
$$;

-- Vrai si la caserne n'est pas suspendue (écriture autorisée).
create function station_writable(p_station uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(
    (select status in ('trialing', 'active', 'past_due') from subscriptions where station_id = p_station),
    true
  );
$$;
```

### Fonctions des paramètres de caserne (migration `0011`, ticket 010)

Quatre fonctions **pures** : elles ne lisent aucune table, ne révèlent rien, et leur exécution
reste ouverte à `authenticated` — une contrainte `check` est évaluée sous l'identité de qui
écrit, et une fonction non exécutable rendrait toute mise à jour impossible.

| Fonction | Signature | Rôle |
|---|---|---|
| `station_settings_valid` | `(p_settings jsonb) returns boolean` `immutable` | Support de la contrainte `stations_settings_valide` : liste blanche de clés, clés obligatoires, types, bornes, format des heures, structure des surcharges (§ 2.1). |
| `station_settings_heure_valide` | `(p_valeur jsonb) returns boolean` `immutable` | Une chaîne `"HH:MM"` de 00:00 à 23:59. |
| `station_settings_entier_valide` | `(p_valeur jsonb, p_min integer, p_max integer) returns boolean` `immutable` | Un entier **sans partie décimale** dans ses bornes : `jsonb_typeof` dit « number » pour 1.5 comme pour 1. |
| `station_settings_cle_surcharge_valide` | `(p_cle text) returns boolean` `immutable` | `mon`…`sun`, ou une date ISO réelle. La date passe par `make_date` et non par un cast : le cast `text -> date` dépend de `DateStyle`, donc n'est pas immuable, et un simple motif accepterait le 30 février. |

Et une fonction de calcul, `stable` parce qu'elle dépend de la base des fuseaux :

| Fonction | Signature | Rôle |
|---|---|---|
| `period_deadline_at` | `(p_year integer, p_month integer, p_deadline_day integer, p_timezone text) returns timestamptz` | La date limite d'une période : le jour limite du mois précédent, 23:59:59, dans le fuseau de la caserne. Une seule écriture de la règle, partagée par le déclencheur de recalcul, le seed et le cron de création des périodes. |

### Fonctions d'invitation (migration `0009`, ticket 006)

Deux fonctions `security definer` **réservées à `service_role`** : elles sont appelées par
les Edge Functions `invite-member` et `accept-invitation`, jamais par un client.

| Fonction | Signature | Rôle |
|---|---|---|
| `create_invitation` | `(p_station uuid, p_email text, p_role membership_role, p_invited_by uuid) returns jsonb` | Vérifie que `p_invited_by` est admin actif de `p_station`, crée ou prolonge la ligne `invitations`, journalise dans `audit_log`. Renvoie le token. |
| `accept_invitation` | `(p_token text, p_user_id uuid, p_email text) returns jsonb` | Vérifie le token, son expiration, qu'il n'est pas déjà accepté et que `p_email` est bien l'adresse invitée ; crée la `memberships` active et marque `accepted_at`, en une transaction. |
| `mask_email` | `(p_email text) returns text` | Masque la partie locale d'une adresse, pour les messages rendus à un porteur de lien qui n'est pas le destinataire. |

Ni exception ni `raise` pour les refus métier : les deux fonctions renvoient
`{"ok": false, "code": …}` et l'Edge Function traduit le code en statut HTTP. La liste des
codes et la forme des réponses HTTP sont dans
[`supabase/functions/README.md`](../supabase/functions/README.md).

Pourquoi du SQL plutôt que plusieurs requêtes depuis Deno : chaque parcours touche
`invitations`, `memberships` et `audit_log` et doit être tout ou rien. Une fonction plpgsql
s'exécute dans une transaction implicite ; trois appels PostgREST, non.

L'exécution est révoquée de `public`, **et nommément de `anon` et `authenticated`** :
`api.auto_expose_new_tables` pose des privilèges par défaut qui accordent `execute` à ces
deux rôles sur toute fonction créée dans `public`, qu'un simple `revoke from public` ne
retire pas. Sans ce verrou, un admin lirait le token en RPC PostgREST — celui-là même que
`0008` a retiré de son `grant` de `select`.

## 4. Row Level Security

RLS activé sur toutes les tables. Principes :

Toutes les politiques sont posées `to authenticated`. `anon` n'a aucune politique et ne lit
rien ; `service_role` et `postgres` ont l'attribut `bypassrls` (Edge Functions, webhooks,
cron). `station_writable()` conditionne **toutes** les écritures métier, membre comme admin :
une caserne suspendue passe en lecture seule. Seules exceptions, volontaires : `stations`
(update) et `profiles`, qui restent modifiables pour permettre de régulariser l'abonnement.

| Table | Lecture | Écriture |
|---|---|---|
| `stations` | membre de la caserne ou super-admin | admin de la caserne ou super-admin (update), super-admin (insert), pas de delete |
| `profiles` | soi-même ; les profils des membres **actifs** de ses casernes ; et, pour un **admin**, ceux de tous les membres de sa caserne quel que soit leur statut (migration `0010` : sans cette branche, un membre désactivé disparaissait de l'écran « Membres » et ne pouvait plus être réactivé) | soi-même |
| `memberships` | membre de la caserne, et toujours ses propres lignes (un compte `invited` ou `disabled` doit pouvoir constater son état) | admin de la caserne, sauf son propre rôle. Aucune politique d'update pour un membre sur sa propre ligne : elle ouvrirait une escalade de privilèges |
| `invitations` | admin de la caserne, **sauf `token`** (retiré du grant de select : c'est un porteur de droits, réservé au service role). Ne jamais faire `select *` sur cette table | admin de la caserne |
| `periods` | membre | admin |
| `availabilities` | membre : les siennes ; admin : toutes celles de la caserne | membre : les siennes si période `open` et caserne writable ; admin : toutes |
| `availability_preferences` | idem availabilities | idem |
| `schedules` | membre si `status <> 'draft'` ; admin toujours | admin |
| `shifts` | membre si le schedule est publié ou validé ; admin toujours | admin |
| `assignments` | membre : les siennes si schedule publié ; tous les membres si validé ; admin toutes | membre : `status` uniquement, de `proposed` vers `accepted` ou `declined`, sur les siennes ; admin : tout |
| `push_tokens` | soi-même | soi-même |
| `notifications` | soi-même | soi-même (`read_at` uniquement, imposé par un grant de colonne : `revoke update on notifications from authenticated` puis `grant update (read_at)`) ; insert par service role |
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

La transition de statut d'une attribution par un membre est verrouillée par trigger. Le
premier garde-fou laisse passer les écritures serveur : sans lui, `publish-schedule` et
`reassign-shift`, qui passent par le service role, seraient rejetées par
« invalid transition ».

Le gel des colonnes est une **liste blanche** : un membre ne fait varier que `status`,
`responded_at`, `decline_reason` et `updated_at`. Une liste noire limitée à `shift_id` et
`user_id` laissait passer `station_id` (déplacement de l'attribution vers une autre
caserne), `was_available`, `reminder_count`, `proposed_at` et `replaced_by`.

```sql
create function assignments_member_transition() returns trigger
language plpgsql set search_path = public, pg_temp as $$
declare
  colonnes_libres constant text[] := array['status', 'responded_at', 'decline_reason', 'updated_at'];
begin
  -- écritures serveur : service_role, postgres, cron, Edge Functions
  if current_user not in ('authenticated', 'anon') then return new; end if;
  if is_admin(new.station_id) then return new; end if;
  if old.user_id <> auth.uid() then raise exception 'forbidden'; end if;
  if old.status <> 'proposed' or new.status not in ('accepted', 'declined') then
    raise exception 'invalid transition';
  end if;
  if new.station_id <> old.station_id
     or new.shift_id <> old.shift_id
     or new.user_id <> old.user_id then
    raise exception 'forbidden';
  end if;
  new.responded_at := now();
  if to_jsonb(new) - colonnes_libres is distinct from to_jsonb(old) - colonnes_libres then
    raise exception 'forbidden';
  end if;
  return new;
end $$;
```

Toute politique d'écriture qui porte une clé étrangère vers une autre table de la caserne
contrôle en outre que la ligne parente a le **même `station_id`** : `shifts.schedule_id`,
`assignments.shift_id` et `assignments.user_id`, `schedules.period_id`,
`availabilities.user_id`, `availability_preferences.period_id` et `.user_id`. Sans ce
contrôle, un admin de A insère un créneau dans un planning de B.

Attention enfin : un `update` sans clause `where` citant une colonne ne sollicite pas les
politiques de `select`. Les conditions de visibilité (statut du planning, par exemple)
doivent donc être répétées dans le `using` de la politique d'`update`, jamais déduites de
la politique de lecture.

Les fonctions trigger (`set_updated_at`, `handle_new_user`, `assignments_member_transition`)
voient leur `execute` révoqué pour `public`, `anon` et `authenticated` : elles n'apparaissent
pas dans le schéma PostgREST et ne sont pas appelables en RPC.

## 5. Triggers

- `set_updated_at` sur toutes les tables avec `updated_at`.
- `handle_new_user` sur `auth.users` : crée la ligne `profiles`.
- `assignments_member_transition` (ci-dessus).
- `memberships_guard_admin` (migration `0010`, ticket 009) : `before update or delete` sur
  `memberships`. Refuse la rétrogradation, la désactivation et la suppression du **dernier
  administrateur actif** d'une caserne (`membership_last_admin`), ainsi que celles qu'un
  administrateur s'appliquerait à lui-même alors qu'un autre admin existe
  (`membership_self_admin_change`). Aucune politique RLS ne sait exprimer « il doit rester au
  moins une ligne qui… » : c'est une contrainte sur l'ensemble de la table. Le déclencheur
  laisse passer le rôle de service (`current_user not in ('authenticated', 'anon')`), comme
  `assignments_member_transition`, et tient `disabled_at` à jour pour tout le monde.
- `stations_check_timezone` (migration `0011`, ticket 010) : `before insert or update of
  timezone` sur `stations`. Refuse un fuseau absent de `pg_timezone_names`
  (`station_timezone_unknown`). Sans lui, un fuseau inventé s'écrit sans bruit et n'échoue
  qu'au premier `make_timestamptz`, dans le cron de verrouillage.
- `stations_recalcule_deadlines` (migration `0011`, ticket 010) : `after update` sur
  `stations`. Recalcule `periods.deadline_at` des périodes `open` de la caserne quand
  `availability_deadline_day` ou le fuseau a changé, et journalise le changement dans
  `audit_log` (`station.settings_updated`, avec l'avant, l'après et le nombre de périodes
  déplacées). **`security definer`, contrairement à `memberships_guard_admin`** : il n'y a ici
  aucun test « est-ce une écriture serveur ? » à fausser, `deadline_at` est une valeur dérivée
  et non une décision d'administration, et laisser la RLS de `periods` rejouer l'arbitrage
  aurait une conséquence absurde — `periods_update_admin` exige `station_writable()` alors que
  l'update de `stations` en est volontairement dispensé (§ 4).
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

### `v_member_last_availability` — dernière saisie d'un membre *(migration `0010`, ticket 009)*

Par (caserne, membre) : `max(availabilities.updated_at)`. C'est la date lue par l'écran
« Membres » pour dire « Dispos saisies le 4 octobre 2026 », et la seule vue déjà livrée.
Déclarée `with (security_invoker = true)` : elle n'accorde aucun droit, elle est lue sous la RLS
de `availabilities` — un admin y voit sa caserne, un membre n'y voit que lui-même. Elle existe
parce que les agrégats PostgREST sont désactivés sur ce projet (`PGRST123`) : sans elle, l'app
rapatrierait toutes les lignes du mois pour n'en garder qu'une par membre.

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
| `invite-member` | app admin | Crée l'invitation et envoie l'email (ticket 006, contrat dans `supabase/functions/README.md`) |
| `accept-invitation` | app, après login | Vérifie le token, crée la membership (ticket 006) |
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
`station_id` côté client. Aucune table n'est encore dans la publication `supabase_realtime`
(elle sera posée avec les plannings, ticket 017).

`invitations` **n'y entrera pas**, et c'est une décision de sécurité, pas un oubli : la
charge utile de `postgres_changes` porte toutes les colonnes publiées. Les politiques RLS
filtrent les *lignes*, pas les *colonnes* — le `grant` de colonne qui cache
`invitations.token` au rôle `authenticated` (`0008`) ne s'applique pas à ce canal. Publier
cette table distribuerait le jeton d'invitation à tous les admins à l'écoute. La liste des
invitations en attente se relit donc par requête (après une action, au retour sur l'écran).

## 10. Migrations

Ordre proposé :
1. `0001_enums_and_stations.sql`
2. `0002_profiles_memberships_invitations.sql`
3. `0003_periods_availabilities_preferences.sql`
4. `0004_schedules_shifts_assignments.sql`
5. `0005_notifications_push_tokens.sql`
6. `0006_subscriptions_audit_super_admins.sql`
7. `0007_functions_rls.sql`
8. `0008_rls_durcissement.sql` (revue du ticket 008 : `pg_temp`, liste blanche du trigger, cohérence du `station_id` avec la ligne parente, token d'invitation)
9. `0009_invitation_functions.sql` (ticket 006 : `mask_email`, `create_invitation`, `accept_invitation`, exécution réservée à `service_role`)
10. `0010_memberships_administration.sql` (ticket 009 : déclencheur `memberships_guard_admin`, vue `v_member_last_availability`)
11. `0011_views.sql`
12. `0012_cron.sql`

Chaque migration est rejouable sur un projet vide et testée en local avec `supabase start`.

Les politiques RLS sont couvertes par `supabase/tests/rls_test.sql`, exécuté par
`scripts/test_rls.sh` (pas de pgTAP : le script lève une exception et rend un code non nul
dès qu'une politique fuit). Les fonctions d'invitation de `0009` sont couvertes par
`supabase/tests/invitations_test.sql`, et le déclencheur de `0010` par
`supabase/tests/memberships_admin_test.sql`, joués par le même script. La couche HTTP des Edge
Functions est testée par `scripts/test_functions.sh`, qui a besoin de
`supabase functions serve` et reste donc local : la CI démarre la pile sans `edge-runtime`.

`supabase/types/database.types.ts` est généré par `scripts/gen_types.sh` et versionné
volontairement : les Edge Functions (section 7) l'importent et la CI doit pouvoir les typer sans
base disponible. C'est la seule exception à la règle « pas de fichier généré commité ». Le
régénérer à chaque migration. La CLI ne produit pas de Dart : les modèles Flutter sont écrits à la
main dans `lib/features/<f>/data/` à partir de ce document.
