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
  'late_responders',
  'subscription_trial_ending',
  'subscription_suspended'
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
  decline_reason  text,                           -- le motif du refus, ou celui de l'annulation
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

**`was_available` et `created_by` sont posés par la base**, jamais déclarés par le client
(déclencheur `assignments_trace_disponibilite`, migration `0018`, ticket 017). `was_available`
est relu à l'insertion dans `availabilities` : sans cela, il suffirait d'envoyer `true` pour
faire disparaître une attribution forcée du journal de la caserne. Même raisonnement que
`availabilities.set_by` (§ 5) — une trace ne se choisit pas.

**En brouillon, retirer une attribution la supprime** : `proposed_at` est nul, rien n'est parti,
il n'y a rien à conserver (`docs/WORKFLOWS.md § 3`). Après publication, la même attribution
s'annule ou se remplace et **reste** : la politique `assignments_delete_admin` (durcie en `0018`)
n'autorise la suppression que si le planning est encore `draft`.

**Les états terminaux (`declined`, `replaced`, `cancelled`) et `replaced_by` sont hors de portée
d'un client** (déclencheur `assignments_guard_reattribution`, migration `0020`, ticket 020). On n'y
**entre** pas par une insertion — une attribution ne naît pas refusée —, on n'en **sort** pas par une
mise à jour — l'historique ne se réécrit pas —, le **motif d'un refus est gelé**, et `replaced_by` ne
se pose pas à la main. Ces écritures passent par `reassign_shift` ou `cancel_assignment`, qui
préviennent le pompier concerné **dans la même transaction** : un changement d'état qui ne se dit pas
laisserait quelqu'un se croire d'astreinte.

Deux règles du même déclencheur valent pour **tout le monde**, rôle de service compris :
`replaced_by` ne désigne jamais la ligne elle-même (`assignment_link_self`) et toujours une
attribution **du même créneau** (`assignment_link_foreign_shift`). Ce n'est pas une règle
d'interface, c'est la cohérence du fil de l'histoire — et rien d'autre n'empêchait un lien de
traverser les créneaux, ni les casernes. `replaced_by` est posé dans les quatre cas de réattribution, y compris quand l'ancienne
attribution reste `declined` ou `cancelled` — c'est le fil qui dit « ce trou-là a été comblé par
cette attribution-là ».

**`decline_reason` porte le motif d'un `declined` comme celui d'un `cancelled`** (migration
`0020`). La colonne répond à « pourquoi cette garde n'est pas tenue » ; `status` dit déjà qui l'a
écrit — le membre en refusant, l'administrateur en annulant. Sans cet élargissement, le suivi
afficherait « annulé » sans jamais pouvoir dire pourquoi.

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

`error` est le seul signal d'échec que le client lit, et il ne lit que sa **présence** :
une ligne `inapp` dont `error` est renseignée s'affiche avec la mention « L'envoi a
échoué, tu ne l'as peut-être pas reçue » (ticket 026), quel que soit le motif rangé
dedans. C'est ce qui permet d'y mettre le motif technique, et donc de n'écrire aucune
phrase destinée au membre ailleurs que dans les chaînes de l'application et
`notification_content.ts`. Une demande de notification abandonnée après cinq tentatives
produit une telle ligne (ticket 040, § 2.16).

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

### 2.17 `stripe_events` — événements de paiement déjà reçus *(migration `0023`, ticket 029)*

```sql
create table stripe_events (
  id            text primary key,          -- « evt_… », l'identifiant du prestataire
  type          text not null,             -- « invoice.paid », …
  station_id    uuid references stations(id) on delete set null,
  status        text not null default 'processing',
  result        jsonb not null default '{}'::jsonb,
  error         text,
  attempts      integer not null default 1,
  received_at   timestamptz not null default now(),
  processed_at  timestamptz,
  constraint stripe_events_status_valide
    check (status in ('processing', 'processed', 'skipped', 'failed'))
);
create index on stripe_events (status, received_at desc) where status <> 'processed';
```

**La signature ne dit pas qu'un événement est neuf**, seulement qu'il vient bien du prestataire.
Un même événement authentique réémis dans la fenêtre de cinq minutes — rejeu manuel depuis le
tableau de bord, double livraison, requête captée — repasse la vérification. Sur
`invoice.payment_failed`, cela ramène en impayé une caserne qui vient de régulariser. La clé
primaire est donc l'identifiant du prestataire : c'est lui qui porte l'unicité, et c'est
l'insertion qui tranche, jamais un test suivi d'une écriture.

Les quatre statuts : `processing` (pris en charge), `processed` (appliqué), `skipped` (écarté —
caserne inconnue, formule inconnue, client incohérent ; le rejouer n'y changerait rien) et
`failed`. **`failed` est le seul que le dédoublonnage laisse reprendre**, et c'est ce qui permet
aux rejeux du prestataire d'aboutir. C'est aussi la trace qui survit à leur abandon au bout de
trois jours : `select * from stripe_events where status <> 'processed'` dit ce qui n'est jamais
passé, comme `notification_outbox` pour les notifications.

RLS active, **aucune politique** : ni `anon` ni `authenticated` n'en lisent une ligne.

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

### 2.16 `notification_outbox` — file d'attente des envois *(migration `0014`, ticket 025)*

```sql
create table notification_outbox (
  id            uuid primary key default gen_random_uuid(),
  station_id    uuid references stations(id) on delete cascade,
  type          notification_type not null,
  recipients    jsonb not null,     -- [{"user_id": uuid, "payload": {…}}]
  payload       jsonb not null default '{}'::jsonb,
  channels      text[],             -- null = canaux par défaut du type (§ 8 de WORKFLOWS)
  dedupe_key    text,
  status        text not null default 'pending'
                  check (status in ('pending', 'sending', 'sent', 'failed')),
  attempts      int not null default 0,
  locked_until  timestamptz,
  last_error    text,
  result        jsonb,
  created_at    timestamptz not null default now(),
  processed_at  timestamptz
);
create index notification_outbox_pending_idx on notification_outbox (created_at)
  where status in ('pending', 'sending');
create unique index notification_outbox_dedupe_uniq on notification_outbox (type, dedupe_key)
  where dedupe_key is not null;
```

**Pourquoi cette table existe, alors que le ticket 025 disait « appel direct par
pg_net ».** `net.http_post` est asynchrone et sans mémoire : il pousse une requête,
un worker la tire, et si l'Edge Function ne répond pas (déploiement en cours, 500,
quota), la requête disparaît. Comme c'est l'Edge Function qui écrit la ligne
`notifications`, une perte ne laisse **aucune trace** : un pompier à qui on a
attribué une astreinte ne l'apprend jamais, et personne ne le sait.

La demande est donc écrite ici, **dans la transaction métier** : elle existe, ou
l'événement n'a pas eu lieu. `notify()` tente ensuite l'appel immédiat — la latence
reste celle d'un appel HTTP — et la tâche `dispatch_notifications` (§ 8) reprend
chaque minute ce qui n'a pas abouti, cinq fois, avant de marquer la ligne `failed`
avec sa dernière erreur. Livraison **au moins une fois**, jamais zéro : un doublon
de notification est un désagrément, une proposition d'astreinte jamais reçue est
une faute.

Et l'abandon lui-même laisse une trace lisible **par le destinataire**, pas seulement
en exploitation : `notify_trace_echec` (§ 3, migration `0022`, ticket 040) remet la
demande en file sur le seul canal `inapp`, et la ligne `notifications` qui en sort porte
son `error`.

`sending` n'est pas un statut décoratif : c'est lui qui rend la prise en charge
**exclusive**. `notify_claim` fait passer la ligne de `pending` à `sending` et ne
rend rien si elle n'y était plus — deux requêtes qui arrivent ensemble (la tentative
immédiate et une reprise qui n'a pas vu le verrou) n'obtiennent la demande qu'une
fois, et le membre ne reçoit pas la notification en double. Une Edge Function qui
meurt après avoir pris la demande la laisse en `sending` ;
`cron_dispatch_notifications` la ramène à `pending` quand son verrou expire, donc une
panne coûte deux minutes de retard, jamais une notification.

`dedupe_key` porte les règles d'unicité métier de `docs/WORKFLOWS.md § 8` — « un
rappel par membre et par échéance » (ticket 015), « un rapport par jour et par
planning » (ticket 022) : deux appels de même type et même clé ne produisent
qu'une ligne, et `notify()` rend l'identifiant de celle qui existe déjà.

RLS activée **sans aucune politique**, et les privilèges retirés à `anon` et
`authenticated` : cette table porte les charges utiles de toutes les casernes à
la fois et n'est lue que par le rôle de service. C'est la seule table du schéma
dans ce cas, et `supabase/tests/rls_test.sql § 9` le vérifie nommément.

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

-- Ce qu'un membre — pas seulement un admin — a le droit de savoir de
-- l'abonnement de sa caserne (migration `0024`, ticket 030).
create function station_access(p_station uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select case
    when not is_member(p_station) then null
    else jsonb_build_object(
           'station_id', p_station,
           'writable',   station_writable(p_station))
         || coalesce(
              (select jsonb_build_object(
                        'status',        s.status,
                        'trial_ends_at', s.trial_ends_at,
                        'suspended_at',  s.suspended_at)
                 from subscriptions s
                where s.station_id = p_station),
              '{"status": null, "trial_ends_at": null, "suspended_at": null}'::jsonb)
  end;
$$;
```

`subscriptions` reste réservée aux administrateurs (`subscriptions_select_admin`) : un simple
membre ne pouvait donc pas savoir **pourquoi** sa grille refusait ses cases. `station_access`
lève ce mystère sans ouvrir la table — quatre faits, et rien du prestataire de paiement. Son
`writable` est calculé par `station_writable()` elle-même : une seule définition du droit
d'écrire, que l'interface ne peut pas contredire. Ouverte à `authenticated`, elle rend `NULL`
à qui n'est pas membre actif.

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

### Fonctions du cycle de vie des périodes (migration `0012`, ticket 014)

| Fonction | Signature | Rôle |
|---|---|---|
| `cron_create_periods` | `(p_reference timestamptz default null) returns integer` | Corps de la tâche `create_periods` (§ 8). Crée les périodes M+1 et M+2 manquantes de chaque caserne, **mois de référence calculé dans le fuseau de chaque caserne** : à 02:00 UTC le 1er du mois, une caserne à UTC-11 est encore dans le mois précédent et un calcul en UTC lui sauterait un mois. Date limite posée par `period_deadline_at`. Idempotente (`on conflict do nothing`) : rejouée, elle ne crée rien et ne réécrit ni le statut ni la date limite d'une période existante. Renvoie le nombre de créations. |
| `cron_lock_periods` | `(p_reference timestamptz default null) returns integer` | Corps de la tâche `lock_periods` (§ 8). Passe en `locked` les périodes `open` dont `deadline_at` est dépassée et pose `locked_at`. Idempotente : la clause `status = 'open'` fait qu'un second passage ne touche rien et n'écrase pas un `locked_at` déjà posé. Renvoie le nombre de verrouillages. |
| `create_period` | `(p_station uuid, p_year integer, p_month integer) returns periods` | Action « créer un mois » de l'écran d'administration. Vérifie `is_admin` puis `station_writable`, refuse un mois écoulé (jugé dans le fuseau de la caserne, `period_month_in_past`) et un mois hors bornes (`period_month_invalid`). Idempotente : renvoie la période existante plutôt qu'une erreur. Seule fonction de la migration ouverte à `authenticated`. |

Le paramètre `p_reference` des deux fonctions de cron n'est pas une commodité : c'est la
seule façon de vérifier en CI, en quelques millisecondes, un comportement dont la période est
le mois. L'ordonnanceur appelle toujours la forme sans argument. Leur exécution est révoquée
de `public`, `anon` et `authenticated` : une tâche qui tourne avec des droits élevés ne doit
pas être un bouton accessible depuis un client.

### Fonctions d'envoi des notifications (migration `0014`, ticket 025)

Le point d'entrée des déclencheurs et des tâches planifiées est `notify(...)`. Tout le
reste — contenu français, regroupement, FCM, courriel, nettoyage des jetons — vit dans
l'Edge Function `send-notification` (§ 7) : signer un jeton OAuth Google en plpgsql
n'aurait aucun sens.

| Fonction | Signature | Rôle |
|---|---|---|
| `notify` | `(p_type notification_type, p_user_ids uuid[] default null, p_station uuid default null, p_payload jsonb default '{}', p_channels text[] default null, p_recipients jsonb default null, p_dedupe_key text default null) returns uuid` | Écrit la demande dans `notification_outbox` **dans la transaction métier**, puis tente l'appel immédiat. Deux façons de décrire les destinataires : `p_user_ids` (tout le monde reçoit la même chose) ou `p_recipients` (`[{"user_id", "payload"}]`, une charge utile par membre — c'est le support du regroupement). Renvoie l'identifiant de la ligne de file. |
| `notify_post` | `(p_outbox uuid) returns boolean` | Poste une ligne vers l'Edge Function par `net.http_post`, incrémente `attempts`, pose un verrou de deux minutes. **Ne lève jamais** : un incident pg_net ne doit pas annuler la publication d'un planning. |
| `notify_claim` | `(p_outbox uuid) returns notification_outbox` | Prend une demande en charge : `pending` → `sending`, verrou de deux minutes. Renvoie `NULL` si elle est déjà prise ou close — la prise en charge est **exclusive**, pas seulement idempotente. Réservée à `service_role`. |
| `notify_complete` | `(p_outbox uuid, p_ok boolean, p_error text default null, p_result jsonb default null) returns void` | Clôt la demande, `sent` ou `failed`, avec son compte rendu. Réservée à `service_role`. |
| `cron_dispatch_notifications` | `(p_reference timestamptz default null, p_limit integer default 100, p_max_attempts integer default 5) returns integer` | Corps de la tâche `dispatch_notifications` (§ 8). Ramène à `pending` les prises en charge dont le verrou a expiré, reprend les demandes restées en attente, abandonne au bout de cinq tentatives et met en file la **ligne interne** de chaque abandon (`notify_trace_echec`, `0022`). Idempotente, paramétrée par un instant de référence comme les tâches de `0012`. |
| `notify_trace_echec` | `(p_outbox uuid) returns uuid` *(migration `0022`, ticket 040)* | Met en file la ligne interne d'une demande abandonnée : même type, mêmes destinataires, même charge utile, `channels = {inapp}`, plus une clé `delivery_failure` (`{outbox_id, attempts, error}`) dans la charge utile commune. Rend `NULL` pour une demande inconnue **ou pour une demande qui est elle-même une trace** — c'est le garde-fou contre la boucle. |
| `notify_endpoint` | `() returns (o_url text, o_secret text)` | Adresse de l'Edge Function et secret d'appel, lus dans Supabase Vault. |
| `notify_internal_secret` | `() returns text` | Le secret d'appel, que l'Edge Function lit pour authentifier ce qui vient de pg_net. Réservée à `service_role`. |

**Un abandon n'est jamais un silence pour son destinataire** *(ticket 040, migration
`0022`)*. Avant, une demande épuisée après cinq tentatives finissait en ligne `failed`
de `notification_outbox`, visible du seul rôle de service : le pompier à qui l'on
proposait une astreinte pouvait ne jamais l'apprendre. `cron_dispatch_notifications`
remet désormais la même demande en file par `notify_trace_echec`, canal `inapp` seul et
marque `delivery_failure` ; `send-notification` la reconnaît, **n'envoie rien** et écrit
la seule ligne `notifications` avec `delivered = false`, `sent_at` nul et `error`
renseignée — la colonne que le centre de notifications traduit en « L'envoi a échoué, tu
ne l'as peut-être pas reçue » (ticket 026).

Le détour par l'Edge Function n'est pas un ornement : le français des notifications vit
dans `supabase/functions/_shared/notification_content.ts`, et l'écrire une seconde fois
en plpgsql en ferait deux endroits à tenir. La trace dit donc « Astreinte proposée le
12 octobre, nuit », pas « une notification a échoué ». Elle hérite au passage de toute la
file : si l'Edge Function est encore en panne — le cas probable, puisque c'est elle qui
vient de faire échouer cinq tentatives — la trace attend et repart à la minute suivante.
Elle peut être abandonnée à son tour, et n'engendre alors **pas** de trace d'elle-même.

**Le secret d'appel n'est recopié nulle part.** La migration l'engendre au hasard et
le range dans Vault ; l'Edge Function va l'y chercher avec sa clé de service. La base
ne peut pas porter la clé de service (ce serait l'écrire en clair dans le seed), et la
fonction ne peut pas deviner un mot de passe qu'on ne lui a pas donné. Aucune étape
manuelle, aucun secret dans le dépôt, la même chose en local et en production.

L'adresse, elle, vise la pile locale par défaut et se remplace en une commande sur un
projet hébergé (`supabase/functions/README.md`).

Exécution révoquée de `public`, `anon` et `authenticated` pour toutes : écrire une
notification à qui l'on veut, dans la caserne que l'on veut, n'est pas un bouton de
client.

### Rappels de saisie (migration `0016`, ticket 015)

| Fonction | Signature | Rôle |
|---|---|---|
| `cron_availability_reminders` | `(p_reference timestamptz default null) returns integer` | Corps de la tâche `availability_reminders` (§ 8). Pour chaque période **ouverte** d'une caserne **non suspendue**, relance les membres **actifs** qui n'ont aucune ligne `availabilities` sur le mois : push à J-3, courriel à J-1. Renvoie le nombre de rappels mis en file. |

Trois points qui font la justesse de cette tâche :

- **Les jours se comptent dans le fuseau de la caserne**, comme le mois de référence de
  `cron_create_periods`. `deadline_at` est un `timestamptz` : sans cette conversion, une
  caserne d'outre-mer serait relancée un jour trop tôt ou un jour trop tard selon le signe
  de son décalage. Le tir quotidien à 09:00 fait avancer la date locale de chaque caserne
  d'exactement un jour : aucune ne saute une échéance, aucune n'en voit deux.
- **« Un seul envoi par membre et par échéance » est la clé de dédoublonnage de `notify`**,
  `availability_reminder:<caserne>:<AAAA-MM>:<j-3|j-1>:<membre>`, pas une colonne d'état.
  L'unicité est celle de l'index `notification_outbox_dedupe_uniq` (`0014`) : un rejeu de
  l'ordonnanceur ne coûte rien. La caserne fait partie de la clé parce qu'un pompier peut
  servir dans deux casernes (`docs/PRD.md § 6.1`) et doit être relancé par chacune.
- **Une saisie, quelle qu'elle soit, dispense du rappel.** Une ligne `absent` compte comme
  une ligne `available` : le membre a répondu. Même définition que `v_period_completion`.

### Construction du planning (migration `0018`, ticket 017)

| Fonction | Signature | Rôle |
|---|---|---|
| `station_required_count` | `(p_settings jsonb, p_date date, p_slot slot_type) returns integer` `immutable` | L'effectif requis d'un créneau : **surcharge datée**, sinon **surcharge de jour de semaine**, sinon `required_day` / `required_night` (§ 2.1). Une surcharge qui ne fixe qu'un créneau laisse l'autre au défaut. Fonction pure, exécution ouverte à `authenticated`. La clé ISO est construite par `lpad`, jamais par `to_char`, qui dépend de `DateStyle` et ne serait pas immuable. |
| `create_schedule` | `(p_station uuid, p_period uuid) returns schedules` | Action « créer le planning du mois ». Vérifie `is_admin` puis `station_writable`, refuse une période étrangère (`period_not_found`), crée le planning en `draft` et **tous ses créneaux** (chaque jour du mois × `slot_type`), `required_count` copié par `station_required_count`. Idempotente aux deux niveaux : rejouée, elle ne crée ni second planning ni créneau en double, et **ne réécrit aucun effectif existant**. |

L'ordre de résolution des surcharges n'est pas arbitraire : une surcharge datée est une
décision prise pour ce jour-là (le réveillon, une manifestation) et doit gagner contre la
règle hebdomadaire, sans quoi elle ne servirait jamais un samedi.

**`create_schedule` est le seul endroit où `settings` devient `required_count`.** Ensuite,
chaque créneau porte son propre effectif et rien en base ne le réécrit : c'est le critère du
ticket 010, vérifié par `supabase/tests/planning_brouillon_test.sql § 2`.

### Publication et suivi d'un planning (migration `0019`, ticket 019)

| Fonction | Signature | Rôle |
|---|---|---|
| `publish_schedule` | `(p_schedule uuid, p_actor uuid) returns jsonb` `security definer`, **réservée à `service_role`** | La publication, **en une transaction** : droit de l'acteur, statut `draft → published`, `proposed_at` posé sur chaque attribution du brouillon, journal `schedule.published`. Rend les destinataires **déjà groupés par membre** — un objet par pompier, ses créneaux triés — prêts pour `send-notification`. Refus métier en `{"ok": false, "code": …}` : `schedule_not_found`, `not_admin`, `station_suspended`, `schedule_not_draft`. |
| `schedule_complet` | `(p_schedule uuid) returns boolean` `stable security definer` | Vrai quand **chaque** créneau atteint son effectif requis en attributions **acceptées**. Écrit une fois, trois appelants : le déclencheur d'acceptation, la fin de `publish_schedule` et le changement d'effectif requis d'un créneau. |
| `schedule_reevaluer` | `(p_schedule uuid) returns boolean` `security definer` | Verrouille la ligne du planning (**`for update` en première instruction**), teste la complétude et applique la transition : `published → validated` avec notification à tous les membres actifs, ou `validated → published` quand un effectif requis a changé. Le verrou précède le test, et c'est toute l'affaire — voir § 5. |
| `remind_schedule` | `(p_schedule uuid, p_tout boolean default false) returns jsonb` `security definer`, ouverte à `authenticated` | La relance manuelle, celle du bouton « Relancer maintenant ». Le retard a **une seule définition dans tout le produit** : celle de `v_schedule_progress.assignments_late`. `p_tout` la lève, pour rattraper un envoi de publication qui n'a pas abouti — les pompiers qui n'ont rien reçu ne sont pas « en retard ». Une notification par membre, et **la marque suit l'envoi** : une demande écartée par la clé de dédoublonnage ne touche ni `reminder_count` ni `last_reminder_at`, sans quoi un double clic ferait croire aux crons du ticket 022 qu'un palier est franchi. Un verrou consultatif sérialise les appels concurrents sur un même planning. |

**Le groupement se fait en SQL, pas en TypeScript.** `send-notification` sait regrouper — c'est sa
promesse et elle est testée chez elle — mais le faire ici le rend vérifiable par
`scripts/test_rls.sh`, qui tourne en CI là où les Edge Functions ne sont pas joignables. Et le
nombre annoncé à l'administrateur (« 18 pompiers notifiés ») vient alors du même comptage que
l'envoi, jamais d'un second.

**L'envoi n'est pas dans la transaction, et c'est délibéré.** Il vient après, depuis l'Edge
Function, et ne peut donc pas défaire une publication acquise : une notification perdue se rattrape
(file de `notify`, relance manuelle, crons du 022), une publication à moitié faite ne se rattrape
pas.

### Réattribution et annulation (migration `0020`, ticket 020)

| Fonction | Signature | Rôle |
|---|---|---|
| `reassign_shift` | `(p_shift uuid, p_user uuid, p_actor uuid, p_previous uuid default null) returns jsonb` `security definer`, **réservée à `service_role`** | La réattribution, **en une transaction** : nouvelle attribution `proposed` avec `proposed_at = now()`, `created_by` et `was_available` posés par la fonction, ancienne marquée `replaced` (`accepted` ou `proposed`) ou **laissée telle quelle** (`declined`, `cancelled` : un statut terminal a déjà été notifié sous ce nom), `replaced_by` posé dans les quatre cas, notifications, `audit_log` et `schedule_reevaluer`. `p_previous` omis sur un créneau qui porte un trou non comblé — un refus ou une annulation : la fonction rattache la nouvelle au **plus ancien** d'entre eux. Seul `replaced` n'est pas remplaçable : ce qui a déjà trouvé son remplaçant ne s'en cherche pas un second. **Deux verrous, dans l'ordre d'une réponse de membre** — l'attribution remplacée, puis le planning —, et **le compte des places** après eux : une réattribution remplace, elle n'ajoute pas. Refus métier en `{"ok": false, "code": …}` : `shift_not_found`, `not_admin`, `station_suspended`, `schedule_not_published`, `member_not_active`, `already_assigned`, `shift_already_filled`, `assignment_not_found`, `assignment_not_replaceable`. |
| `cancel_assignment` | `(p_assignment uuid, p_reason text default null) returns jsonb` `security definer`, ouverte à `authenticated` | L'annulation d'une attribution d'un planning publié : statut `cancelled`, motif conservé dans `decline_reason`, notification `assignment_cancelled` **si la garde était acceptée**, `audit_log` et `schedule_reevaluer`. Refus : `assignment_not_found`, `not_admin`, `station_suspended`, `schedule_not_published`, `assignment_not_active`. |

**Une notification, et une seule, sauf quand une garde acquise disparaît.** Un refus suivi d'une
réattribution ne produit qu'un envoi : `assignment_proposed` au nouveau membre. Celui qui a refusé
n'est pas prévenu — il sait. Celui qui n'avait pas encore répondu non plus : `docs/WORKFLOWS.md § 3`
marque la notification sur les seules transitions venues d'`accepted`, et une proposition retirée
avant réponse disparaît simplement de son écran. Seul le pompier dont la garde était **acceptée**
reçoit `assignment_cancelled` — c'est le seul à qui on retire quelque chose.

**`assignment_cancelled` et non `assignment_changed` pour l'ancien titulaire.** De son point de vue
rien n'a « changé » : il n'a plus cette garde. Le lien profond d'`assignment_cancelled` mène au
planning du mois, là où il vérifiera ; celui d'`assignment_changed` mène à l'écran des propositions,
où il n'a plus rien à faire.

**Les notifications sont posées dans la transaction, par `notify(...)`.** Contrairement à
`publish_schedule`, qui rend ses destinataires à l'Edge Function pour un envoi postérieur, il n'y a
ici ni regroupement à faire ni compte rendu à montrer — et la file garantit le rejeu si le processus
appelant meurt. Un pompier qui ignore qu'il est d'astreinte est le seul défaut que ce geste n'a pas
le droit de produire.

### Relances automatiques (migration `0021`, ticket 022)

| Fonction | Signature | Rôle |
|---|---|---|
| `assignment_reminder_targets` | `(p_schedule uuid, p_palier text, p_instant timestamptz default null) returns uuid[]` `stable` | Les attributions dues à un palier, à un instant. `push` : `proposed`, jamais relancée, proposée depuis plus de `response_reminder_hours`. `email` : relancée une fois — ou plusieurs, mais aucune depuis `response_email_hours`. Membre **actif** et planning **publié** dans les deux cas. `NULL` quand personne n'est dû. |
| `cron_assignment_reminders` | `(p_reference timestamptz default null) returns integer` | Corps de la tâche `assignment_reminders` (§ 8). Une notification **par membre** et par palier, ses gardes groupées dedans, canaux `push + inapp` puis `email + inapp`. Renvoie le nombre de notifications mises en file. |
| `cron_late_responders_report` | `(p_reference timestamptz default null) returns integer` | Corps de la tâche `late_responders_report` (§ 8). Prévient les administrateurs actifs des attributions sans réponse depuis plus de `late_report_hours`, **une fois par jour et par planning**, entre 08:00 et 20:59 dans le fuseau de la caserne. Renvoie le nombre de rapports mis en file. |

Les trois délais viennent des `settings` de **chaque caserne** (§ 2.1) : aucune constante
d'heures n'est écrite dans la migration.

**Le retard a une seule définition, et elle a désormais trois lecteurs** :
`v_schedule_progress.assignments_late` (§ 6), `remind_schedule` (0019) et
`cron_late_responders_report`. L'égalité des trois est vérifiée par
`supabase/tests/assignment_reminders_test.sql § 7 bis`, au même instant et sur le même
planning. Une seule différence, volontaire : les **relances** écartent les membres inactifs
— une proposition laissée à un pompier désactivé n'a plus de destinataire —, le **rapport**
les compte, parce qu'un trou dans le planning doit se voir chez l'administrateur.

**La marque suit l'envoi.** `reminder_count` et `last_reminder_at` ne bougent que lorsqu'une
demande est réellement mise en file : une demande écartée par la clé de dédoublonnage ne
marque rien. C'est la règle posée en revue du ticket 019, et elle est ici la condition de
justesse des paliers — marquer sans envoyer ferait passer un pompier au palier suivant sans
qu'il ait rien reçu.

**Cohabitation avec la relance manuelle.** `remind_schedule` incrémente le même compteur.
Le comportement retenu : une relance manuelle **tient lieu de premier palier** (le push de
`response_reminder_hours` est sauté, le pompier vient d'être relancé) mais **aucun nombre de
clics ne fait sauter le courriel**. D'où la seconde branche de la condition du palier
courriel : « plusieurs relances, mais aucune depuis l'échéance ». Elle couvre aussi la
reprise après une panne longue de l'ordonnanceur, où le push part bien après l'échéance du
courriel.

**Le rapport quotidien ne tombe pas au milieu de la nuit locale.** La tâche est horaire et sa
clé de dédoublonnage porte la **date locale de la caserne** ; sans fenêtre, la première
exécution après minuit local aurait envoyé un push à 00:45. La fenêtre `08:00 – 20:59` locale
règle le cas, et répond pour cette tâche à la question du ticket 041 — qui reste entier pour
`availability_reminders` (0016), dont le tir quotidien unique est à une heure de serveur.

Exécution révoquée de `public`, `anon` et `authenticated` pour les trois : une tâche qui
tourne avec des droits élevés n'est pas un bouton de client. Le bouton, c'est
`remind_schedule`.

### Abonnement par caserne (migration `0023`, ticket 029)

| Fonction | Rôle |
|---|---|
| `subscription_bootstrap()` | Déclencheur `after insert` sur `stations` : toute caserne naît en `trialing` avec `trial_ends_at = now() + 60 jours`. **L'essai est géré côté application, sans carte bancaire** (`docs/PRD.md § 6.6`) — aucun essai n'est déclaré chez le prestataire. `on conflict do nothing` : une ligne posée à la main reste telle quelle |
| `subscription_sync(p_station, p_customer, p_subscription, p_status, p_plan, p_period_end, p_event, p_event_id, p_reference)` | **Le seul chemin d'écriture de `subscriptions`.** Appelée par `stripe-webhook` une fois la signature vérifiée. Dédoublonnée sur `p_event_id` via `stripe_events` (§ 2.17) : un rejeu rend `duplicate` sans rien réappliquer, un traitement en échec se reprend. Retrouve la caserne par `p_station` (le `client_reference_id` de la session) ou par `p_customer` ; **refuse (`customer_mismatch`) si les deux ne vont pas déjà ensemble** (voir ci-dessous) ; verrou de ligne ; les paramètres **nuls ne remplacent rien**, ce qui rend les cinq événements applicables dans n'importe quel ordre ; tient `suspended_at` ; journalise `subscription.<événement>` dans `audit_log`. Une caserne introuvable rend `station_not_found` sans erreur — l'événement ne nous concerne pas |
| `stripe_event_close(p_event_id, p_station, p_code)` | Marque un événement `skipped` et rend le refus. Un refus **consomme** l'événement : une caserne inconnue ne le deviendra pas |
| `stripe_event_fail(p_event_id, p_type, p_error)` | Trace durable d'un traitement en échec, posée par l'Edge Function **hors de la transaction annulée** — celle posée à l'intérieur est partie avec elle |
| `subscription_set_customer(p_station, p_customer)` | Retient l'identifiant client du prestataire **sans toucher au statut** : au moment où `create-checkout` crée le client, rien n'est encore payé |
| `cron_suspend_subscriptions(p_reference)` | Corps de la tâche `suspend_subscriptions` (§ 8). Deux populations : essai expiré **sans abonnement souscrit** (la condition sur `stripe_subscription_id` évite de suspendre une caserne qui vient de payer), et `past_due` dont `coalesce(current_period_end, updated_at)` remonte à plus de quatorze jours. Idempotente |

Les trois premières sont réservées au rôle de service ; la quatrième à l'ordonnanceur. Aucune
n'est appelable par `anon` ni `authenticated`.

**Pourquoi `subscription_sync` vérifie que le client va avec la caserne.** La signature établit que
l'appel vient du prestataire, **pas** que la caserne nommée est la bonne : `client_reference_id`
est un champ que l'on peut poser depuis une URL, un lien de paiement public l'accepte en paramètre.
Sans contrôle, un événement qui nomme la caserne B avec le client de A fait basculer B en `active`
**et lui recolle le client de A** — après quoi l'administrateur de B ouvre le portail de A : sa
carte, ses factures, sa résiliation. Deux garde-fous, qui ne font pas double emploi : la caserne
visée ne doit pas porter **un autre** client, et le client ne doit pas être **déjà pris** par une
autre caserne. Dans les deux cas, rien n'est écrit et le code `customer_mismatch` est rendu — que
l'Edge Function traite comme une caserne inconnue.

**Pourquoi `current_period_end` et non `updated_at`** pour dater un impayé : le prestataire
n'avance `current_period_end` qu'après un paiement réussi, alors qu'`updated_at` bouge à **chaque**
tentative de carte. Compter les quatorze jours sur `updated_at` repousserait indéfiniment la
suspension d'une caserne dont la carte est relancée tous les trois jours.

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
| `schedules` | membre si `status <> 'draft'` ; admin toujours | admin, **sauf le `delete`, réservé aux plannings encore `draft`** (migration `0019`), et sauf les transitions de statut interdites par `docs/WORKFLOWS.md § 2`, que `schedules_guard_transition` refuse à tout le monde |
| `shifts` | membre si le schedule est publié ou validé ; admin toujours | admin, **sauf le `delete`, réservé aux créneaux d'un planning encore `draft`** (migration `0019`) : supprimer un créneau publié effacerait ses attributions par cascade |
| `assignments` | membre : les siennes si schedule publié ; tous les membres si validé ; admin toutes | membre : `status` uniquement, de `proposed` vers `accepted` ou `declined`, sur les siennes ; admin : tout, **sauf le `delete`, réservé aux plannings encore `draft`** (migration `0018`) |
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
- `schedules_guard_transition` (migration `0019`, ticket 019) : `before update` sur
  `schedules`. Impose **la machine à états du § 2 de `docs/WORKFLOWS.md`** — `draft →
  published`, `published → validated | archived`, `validated → published | archived`, et
  rien d'autre (`schedule_invalid_transition`). **Aucun retour en brouillon n'est possible,
  pour personne**, rôle de service compris : sans cette garde, ramener un planning publié en
  brouillon puis supprimer une attribution effaçait une proposition déjà partie, en deux
  écritures. Gèle en outre la clé (`station_id`, `period_id`) — `schedule_key_immutable` — et
  tient les deux horodatages : `published_at` est posé à la **première** publication et jamais
  réécrit, `validated_at` est posé à la validation et **effacé** au retour en `published`.
  Security invoker, comme `periods_guard_transition` : une machine à états est une propriété
  du domaine, pas une règle d'interface.
- `schedules_guard_suppression` et `shifts_guard_suppression` (migration `0019`, ticket 019) :
  `before delete` sur `schedules` et sur `shifts`. Refusent la suppression d'un planning ou
  d'un créneau qui n'est plus en brouillon (`schedule_delete_published`,
  `shift_delete_published`). **Ce sont eux qui attrapent la cascade** : une suppression en
  cascade ne consulte aucune politique RLS, mais elle déclenche bien les triggers de ligne de
  la table enfant. Garder les plannings seuls ne suffisait pas : `shifts` cascade vers
  `assignments`, et supprimer **un créneau** d'un planning publié effaçait les attributions
  qu'un pompier avait déjà reçues — une écriture, aucune trace. Les deux politiques,
  restreintes au brouillon par la même migration, rendent le refus lisible à un client mais ne
  suffisent jamais seules.
- `shifts_effectif_revalide` (migration `0019`, ticket 019) : `after update of required_count`
  sur `shifts`. Change l'effectif requis d'un créneau, et la **condition de validation** du
  planning vient de bouger sans qu'aucune réponse ne l'ait fait : ramener un créneau publié de
  2 à 1 alors qu'une seule personne a accepté rend le planning complet, et aucune réponse ne
  viendra plus le réveiller ; le porter de 1 à 2 sur un planning validé le rend incomplet, et
  le laisser « validé » mentirait à toute la caserne. Appelle `schedule_reevaluer`, qui traite
  les deux sens.
- `assignments_guard_reattribution` (migration `0020`, ticket 020) : `before insert or update` sur
  `assignments`. Quatre règles, dont chacune a été franchie en revue avant d'être écrite :
  **on n'entre pas** dans un état terminal par une insertion (`assignment_transition_reserved` —
  sinon un client fabrique un refus que personne n'a prononcé) ; **on n'en sort pas** par une mise
  à jour (`assignment_transition_terminal` — sinon un refus redevient une proposition sans que rien
  ne parte, et un remplacement ressuscite en acceptation avec son lien) ; **le motif d'un refus est
  gelé** (`assignment_reason_frozen` — il appartient au pompier qui l'a écrit) ; **`replaced_by` ne
  se pose pas à la main** (`assignment_link_reserved`) et ne désigne ni la ligne elle-même
  (`assignment_link_self`) ni une attribution d'un autre créneau
  (`assignment_link_foreign_shift`) — ces deux dernières pour tout le monde. Sans ce déclencheur,
  `assignments_update_admin` et `assignments_insert_admin` (`0008`) laissaient un administrateur
  retirer sa garde à quelqu'un d'une requête PostgREST, **sans que rien ne parte** : le pompier
  notait la date et ne venait pas. Security invoker et nommé pour passer **avant**
  `assignments_member_transition`, pour les deux raisons déjà données à propos
  d'`assignments_trace_disponibilite`.
- `schedule_auto_validate` (migration `0019`, ticket 019 ; clause `when` élargie par `0020`) :
  `after update` sur `assignments`, `when (new.status is distinct from old.status and (new.status
  = 'accepted' or old.status = 'accepted'))`. Délègue à `schedule_reevaluer` : si **chaque**
  créneau du planning atteint son effectif requis en attributions **acceptées** — la validation se
  juge sur les acceptations seules, jamais sur `v_schedule_progress.shifts_filled` (§ 6) —, le
  planning passe en `validated` et `schedule_validated` part à tous les membres actifs.

  **Les deux sens, depuis le ticket 020.** Une acceptation qui *disparaît* — remplacée ou annulée —
  retire une acceptation : un planning `validated` cesse d'être complet et doit repasser en
  `published` (`docs/WORKFLOWS.md § 2`), sans quoi la caserne lirait « Validé » sur un mois à trou.
  `schedule_reevaluer` traitait déjà ce cas depuis le `0019` ; il lui manquait un appelant. Ce
  retour ne notifie personne : la conséquence est déjà partie, à la personne concernée.

  **Le verrou de ligne précède le test, et c'est structurel.** Deux membres qui acceptent en
  même temps les deux places d'un créneau qui en demande deux lisent chacun leur instantané et
  ne voient pas l'acceptation de l'autre : sans verrou, aucun des deux ne conclut « complet »,
  le planning reste publié **pour toujours**, et aucune réponse ultérieure ne viendra le
  réveiller — il n'en reste plus à donner. Arbitrer *après* le test, par un `update … where
  status = 'published'`, ne sert à rien : aucune des deux transactions n'atteint l'arbitrage.
  Avec `select … for update` en première instruction, la seconde attend la première et reprend
  un instantané frais en `read committed`. L'arbitrage reste, en seconde sécurité.
  Reproduit à deux sessions réelles par `scripts/test_concurrence.sh`.

  **La complétude ne se teste pas qu'à l'acceptation.** Un planning dont tous les créneaux
  demandent zéro personne est complet avant la moindre réponse ; `publish_schedule` interroge
  donc `schedule_complet` à son tour, dans la même transaction que la publication. Et
  `schedule_validated` part **sans clé de dédoublonnage** : l'exclusivité est déjà tenue par
  la transition, et une clé « par seconde » avalerait une revalidation légitime survenue dans
  la même seconde.
- `periods_guard_transition` (migration `0012`, ticket 014) : `before update` sur `periods`.
  Tient `locked_at` à jour avec le statut, gèle la clé (`station_id`, `year`, `month`)
  — `period_key_immutable` — et **refuse une réouverture dont la date limite est déjà
  passée** (`period_reopen_deadline_passed`). Ce dernier point est la moitié manquante de
  l'idempotence du cron : sans lui, « rouvrir » est une action que la tâche horaire défait
  dans l'heure, et l'admin en accuse le logiciel. Rouvrir, c'est nécessairement dire jusqu'à
  quand. Security invoker : aucune lecture privilégiée, et la règle vaut aussi pour le rôle
  de service. Étendu par `0013` : une date limite ne peut pas non plus **reculer dans le
  passé** sur un mois déjà `open` (`period_deadline_in_past`), même symptôme et même refus.
  Cette dernière règle ne s'applique qu'aux écritures clients — le recalcul de `0011` est
  `security definer`, donc `current_user` y vaut le propriétaire de la fonction et il passe
  à travers : un admin qui avance le jour limite de sa caserne décide de fermer les mois en
  cours, et refuser son réglage entier pour une date dérivée serait un contresens.
- `availabilities_trace_auteur` (migration `0012`, ticket 014) : `before insert or update`
  sur `availabilities`. Impose `set_by = auth.uid()` pour toute écriture client. La trace de
  l'auteur ne se choisit pas : laissée au client, un admin y écrirait l'identifiant du membre
  et ferait disparaître son intervention de l'écran comme du journal. Les écritures serveur
  (seed, rôle de service) gardent la valeur qu'elles fournissent, comme pour
  `memberships_guard_admin`.
- `audit_admin_actions` : sur `availabilities` quand `set_by <> user_id`, sur `periods`
  quand `status` passe de `locked` à `open`, sur `assignments` quand `was_available = false`.
  **Éclaté en déclencheurs par table** plutôt qu'en une fonction unique (migration `0012`) :
  les trois sémantiques n'ont rien de commun, et une clause `when` par table évite d'appeler
  la fonction sur les écritures ordinaires — une saisie de mois complet, c'est une soixantaine
  de lignes par membre. À ce jour :
  `periods_audit_reouverture` (`after update … when (old.status = 'locked' and new.status = 'open')`)
  → `period.reopen` ;
  `availabilities_audit_saisie_admin` (`after insert or update … when (new.set_by is distinct from new.user_id)`)
  → `availability.set_for_member` ;
  `availabilities_audit_effacement_admin` (`after delete … when (auth.uid() is distinct from old.user_id)`)
  → `availability.cleared_for_member`, parce que décocher une case est une suppression de
  ligne (§ 2.6) et qu'un effacement fait pour autrui doit laisser autant de trace qu'une
  saisie. Le volet `assignments` est arrivé avec les plannings (migration `0018`, ticket 017) :
  `assignments_audit_hors_dispo` (`after insert … when (new.was_available is false)`) →
  `assignment.force`, avec la date et le créneau dans `data`. Il ne couvre que l'insertion :
  publier ou répondre ne force rien.
- `assignments_trace_disponibilite` (migration `0018`, ticket 017) : `before insert` sur
  `assignments`. Impose `created_by = auth.uid()` et **calcule `was_available`** depuis les
  lignes `availabilities` du créneau, pour toute écriture client. Les écritures serveur gardent
  ce qu'elles fournissent (`current_user not in ('authenticated', 'anon')`). **Security
  invoker, et c'est structurel** : en `security definer`, `current_user` vaudrait le
  propriétaire de la fonction, le test « écriture serveur ? » répondrait oui pour tout le monde
  et la trace ne serait jamais posée. Le même piège vaut pour `availabilities_trace_auteur` et
  `assignments_member_transition`, qui sont invoker pour la même raison.
- `periods_audit_creation` et `periods_audit_suppression` (migration `0013`, revue du
  ticket 014) : `after insert` / `after delete` sur `periods`, `period.created` et
  `period.deleted`. Sans elles, la trace de réouverture se contournait sans rien laisser —
  supprimer la période, la recréer par `create_period`, repousser sa date limite, et le mois
  était rouvert avec un `audit_log` vide. Rien ne rattachant les disponibilités à la période
  (`availabilities` porte une date, pas un `period_id`), la manœuvre ne coûtait même pas les
  données saisies : la trace de suppression compte donc les disponibilités du mois qui lui
  survivent. La création n'est journalisée que `when (auth.uid() is not null)` — la tâche
  `create_periods` et le seed en créent par dizaines sans acteur humain, et `audit_log` est
  le journal des administrateurs (§ 2.14), pas celui de la machine. La suppression, elle, est
  journalisée sans condition : c'est une perte de données. Elle s'abstient dans un seul cas,
  la cascade d'une caserne supprimée, où la ligne d'audit référencerait une caserne déjà
  disparue et ferait échouer la suppression sur une clé étrangère.

## 6. Vues

### `availability_matrix(p_station, p_period)` — matrice admin d'un mois *(migration `0017`, ticket 016)*

Une fonction `security definer` et non une vue : elle porte le contrôle d'accès (`forbidden`
si l'appelant n'est pas admin de la caserne, `period_not_found` si la période n'est pas la
sienne) et les filtres.

**Une ligne par membre actif**, et non par cellule. Le document annonçait « une ligne par
(membre actif, date, créneau) » ; la mesure a tranché autrement au ticket 016. À 60 membres ×
31 jours × 2 créneaux, une ligne par cellule fait 3 720 objets JSON qui répètent chacun le
membre, la date et le créneau — ~410 ko sur le fil et autant de `Map` à construire en Dart,
pour une grille qui se relit ensuite cellule par cellule à chaque image. Le mois est donc
encodé en **deux chaînes de longueur fixe**, un caractère par jour :

| Colonne | Type | Contenu |
|---|---|---|
| `user_id` | `uuid` | membre actif de la caserne |
| `display_name` | `text` | surnom de la caserne, à défaut « prénom nom » |
| `first_name`, `last_name` | `text` | le profil, pour trier ou chercher autrement |
| `comment` | `text` | le commentaire du mois écrit par le membre (§ 2.7), `null` s'il n'en a pas |
| `max_shifts`, `max_weekends` | `integer` | plafonds déclarés, `null` = illimité |
| `shifts_count`, `weekend_units` | `integer` | charge du mois |
| `shifts_left`, `weekends_left` | `integer` | restes, `null` si illimité, **négatifs** si dépassés |
| `accepted_previous` | `integer` | astreintes acceptées sur les trois mois précédents |
| `day_slots`, `night_slots` | `text` | un caractère par jour du mois : `.` non saisi, `D`/`d` disponible, `A`/`a` absent — **minuscule si la case a été saisie par un administrateur** (`set_by <> user_id`) |

La position `i` (0 en tête) de `day_slots` et `night_slots` est le jour `i + 1` ; leur longueur
est le nombre de jours du mois. **La casse est la seule différence** : qui l'ignore retrouve
exactement les trois états du § 2.6, et le test le vérifie. Une ligne sans `set_by` — antérieure
au déclencheur `availabilities_trace_auteur` (`0012`) — compte comme saisie par le membre. Les sept colonnes de quotas **viennent de `v_member_load`**,
elles n'en sont pas une seconde écriture.

La fonction ne saisit pas : l'admin qui touche une cellule écrit dans `availabilities` par
l'upsert habituel, autorisé par `availabilities_*_admin` et tracé par `availabilities_trace_auteur`
(§ 5).

### `v_member_load` — charge d'un membre *(migration `0017`, ticket 016)*

Par (station, user actif, period), toujours une ligne même sans attribution ni préférence :
`shifts_count` (astreintes proposées **ou** acceptées du mois), `weekend_units` (unités de
weekend distinctes couvertes), `max_shifts` / `max_weekends` (plafonds déclarés, `null` =
illimité), `shifts_left` / `weekends_left` (plafond moins charge — `null` si illimité, négatif
si dépassé, parce que le PRD § 5.3 autorise l'admin à passer outre avec avertissement) et
`accepted_previous` (astreintes **acceptées** sur les trois mois calendaires précédents, pour
le tri des candidats du ticket 017 et l'équilibrage du 018).

« Les trois périodes précédentes » se lit « les trois mois calendaires précédents » : un mois
qu'une caserne n'aurait pas ouvert n'a pas fait disparaître les astreintes tenues, et faire
dépendre un historique de l'existence de lignes dans `periods` le rendrait faux au premier trou.

`security_invoker = true`, comme les autres vues. Les nombres ne sont donc justes que pour un
**admin** ; un membre y voit les lignes de ses collègues avec des plafonds `null` et des charges
à zéro — vue partielle, pas fuite. **Lue directement par un client, elle coûte un ordre de
grandeur de plus** que lue depuis `availability_matrix` : la RLS d'`assignments` et de `shifts`
(trois politiques permissives, deux `exists`, `is_admin()` non inlinable) est réévaluée sur
chaque ligne examinée. Les écrans qui en ont besoin passent par une fonction `security definer`
qui contrôle l'admin en tête, ou par la clé de service.

#### Le calendrier français, en base *(migration `0017`)*

`weekend_units` suppose une définition de l'unité de weekend, et elle doit être **exactement**
celle du client (`lib/features/dispos/domain/disponibilite_mois.dart`, ticket 013) : samedi et
dimanche forment une seule unité désignée par son samedi, un férié du lundi au vendredi forme
la sienne, un férié tombant un samedi ou un dimanche ne double pas l'unité.

| Fonction | Signature | Rôle |
|---|---|---|
| `paques_gregorien` | `(p_annee integer) returns date` `immutable` | Dimanche de Pâques, comput de Meeus/Butcher. Miroir de `paquesGregorien()`. |
| `jours_feries_fr` | `(p_annee integer) returns date[]` `immutable` | Les onze fériés métropolitains. Alsace-Moselle non traitée, comme côté application. |
| `est_jour_ferie` | `(p_date date) returns boolean` `immutable` | Miroir de `estJourFerie()`. |
| `unite_weekend` | `(p_date date) returns date` `immutable` | L'unité de weekend d'une date, `null` si le jour n'en fait partie d'aucune. Miroir de `uniteWeekend()`. |

**Calculées, jamais tabulées** : l'application ouvre des mois deux mois à l'avance,
indéfiniment, et une table de fériés sur trois ans périmerait en silence — un weekend
disparaîtrait du compteur sans qu'aucune requête n'échoue.

Le même nombre étant produit des deux côtés, la parité est **testée** des deux côtés contre un
corpus unique de quinze années : `supabase/tests/matrice_admin_test.sql § 1-2` et
`test/core/l10n/jours_feries_parite_base_test.dart` portent la même table, et l'un des deux
rougit dès que l'un des deux calculs bouge.

### `v_member_last_availability` — dernière saisie d'un membre *(migration `0010`, ticket 009)*

Par (caserne, membre) : `max(availabilities.updated_at)`. C'est la date lue par l'écran
« Membres » pour dire « Dispos saisies le 4 octobre 2026 », et la seule vue déjà livrée.
Déclarée `with (security_invoker = true)` : elle n'accorde aucun droit, elle est lue sous la RLS
de `availabilities` — un admin y voit sa caserne, un membre n'y voit que lui-même. Elle existe
parce que les agrégats PostgREST sont désactivés sur ce projet (`PGRST123`) : sans elle, l'app
rapatrierait toutes les lignes du mois pour n'en garder qu'une par membre.

### `v_period_completion` — taux de saisie d'un mois *(migration `0013`, revue du ticket 014)*

Une ligne par période : `period_id`, `station_id`, `year`, `month`, `active_members`
(les appartenances `active` de la caserne) et `members_with_availability` (ceux qui ont **au
moins une** ligne de `availabilities` sur le mois). Une période d'une caserne sans membre
actif y figure avec `0` et `0` : l'écran doit pouvoir dire « aucun membre actif » plutôt
qu'afficher « 0 % ».

Le numérateur se construit à partir du même ensemble que le dénominateur : un membre
désactivé depuis qu'il a saisi ne produit pas « 10 membres sur 9 ».

Déclarée `with (security_invoker = true)`, comme `v_member_last_availability`. Les deux
nombres ne sont donc justes que pour un **admin**, seul à lire toutes les disponibilités de
sa caserne (`availabilities_select_own_or_admin`) ; un membre ordinaire y lit un numérateur
de 0 ou 1 — une vue partielle, pas une fuite, et l'écran qui la consomme lui est de toute
façon fermé.

Elle existe parce que compter côté client était **faux sans le dire** : PostgREST plafonne
une réponse à mille lignes et rend `200` sans en-tête d'alerte. À ~62 lignes de
disponibilités par membre et par mois, le compte devenait faux dès dix-sept membres et
plafonnait vers seize — « 16 membres sur 60 ont saisi » alors que les 60 avaient saisi.

### `v_schedule_progress` — avancement d'un planning *(migration `0018`, ticket 017)*

Une ligne par planning. `security_invoker`, comme `v_member_load` : la vue n'accorde aucun
droit.

| Colonne | Sens |
|---|---|
| `schedule_id`, `station_id`, `period_id`, `status` | la clé et l'état du planning |
| `shifts_total` | créneaux du planning |
| `shifts_filled` | créneaux dont les attributions **actives** (`proposed` + `accepted`) atteignent `required_count` |
| `assignments_pending` / `_accepted` / `_declined` | attributions par statut |
| `assignments_late` | attributions `proposed` dont `proposed_at` dépasse `late_report_hours` |

**`shifts_filled` se compte sur les attributions actives, pas sur les seules acceptations.**
C'est le sens de la construction : en brouillon, rien n'est accepté et un planning complet doit
se voir complet. La **validation**, elle, se juge sur les acceptations seules
(`schedule_auto_validate`, § 5) et ne se lit pas ici — deux questions différentes, deux
chiffres, jamais l'un pour l'autre.

`assignments_late` ignore tout le brouillon : `proposed_at is null` n'est jamais en retard,
même règle que les crons de relance (`docs/WORKFLOWS.md § 3`).

## 7. Edge Functions

| Fonction | Déclencheur | Rôle |
|---|---|---|
| `send-notification` | appel interne : `public.notify(...)` → pg_net (déclencheurs, crons), ou HTTP direct depuis une autre Edge Function | Prend un `notification_type`, des destinataires, une caserne et une charge utile ; regroupe, construit le texte français, écrit la ligne `inapp`, envoie le push FCM à tous les appareils du membre, envoie le courriel si le canal est demandé ou si le membre n'a aucun appareil, supprime les jetons définitivement rejetés (ticket 025, contrat dans `supabase/functions/README.md`) |
| `publish-schedule` | app admin | Appelle `publish_schedule` (SQL, atomique), puis `send-notification` avec les destinataires **déjà groupés par membre** : sept créneaux font une notification, pas sept (ticket 019, contrat dans `supabase/functions/README.md`) |
| `reassign-shift` | app admin | Appelle `reassign_shift` (SQL, atomique) : l'ancienne attribution est marquée `replaced` ou reste `declined`, la nouvelle est créée `proposed` et horodatée, `replaced_by` relie les deux, et **une seule** notification part — au nouveau membre, plus l'ancien si sa garde était acceptée (ticket 020, contrat dans `supabase/functions/README.md`). L'annulation, elle, est une RPC (`cancel_assignment`) et non une Edge Function |
| `auto-propose` | app admin | Heuristique de remplissage du brouillon |
| `invite-member` | app admin | Crée l'invitation et envoie l'email (ticket 006, contrat dans `supabase/functions/README.md`) |
| `accept-invitation` | app, après login | Vérifie le token, crée la membership (ticket 006) |
| `stripe-webhook` | Stripe | **Vérifie la signature de l'événement** (HMAC-SHA256 du corps brut, lu sous un plafond d'un mégaoctet, fenêtre de cinq minutes), puis applique les cinq événements de l'abonnement par `subscription_sync`. Un événement non signé, mal signé ou hors de la fenêtre est refusé en 4xx ; un événement **déjà traité** est reconnu par `stripe_events` et n'est pas réappliqué ; sans secret configuré, **tout** est refusé en 503 (ticket 029, contrat dans `supabase/functions/README.md`) |
| `create-checkout` | app admin | Trois actions pour l'écran « Abonnement » : `state` (statut, tarifs, configuration — **répond même sans compte Stripe**), `checkout` (crée le client si besoin, ouvre la session, rend l'adresse) et `portal` (portail de gestion). Rôle d'administrateur revérifié en base (ticket 029, contrat dans `supabase/functions/README.md`) |
| `ics-feed` | GET public avec token par membre | Génère le flux calendrier des astreintes acceptées |
| `export-user-data` | app | Export RGPD en JSON |

## 8. Tâches planifiées (pg_cron)

| Nom | Fréquence | Action |
|---|---|---|
| `create_periods` | 1er du mois, 02:00 | `select public.cron_create_periods();` — crée les périodes M+1 et M+2 manquantes pour chaque caserne *(migration `0012`)* |
| `lock_periods` | toutes les heures | `select public.cron_lock_periods();` — passe en `locked` les périodes dont `deadline_at < now()` *(migration `0012`)* |
| `dispatch_notifications` | chaque minute | `select public.cron_dispatch_notifications();` — repose les demandes de `notification_outbox` restées en attente, abandonne au bout de cinq tentatives et met en file la ligne interne de chaque abandon *(migrations `0014` et `0022`)* |
| `availability_reminders` | tous les jours 09:00 | `select public.cron_availability_reminders();` — push J-3 et email J-1 aux membres actifs sans aucune ligne `availabilities` sur le mois d'une période ouverte *(migration `0016`)* |
| `assignment_reminders` | toutes les heures (:15) | `select public.cron_assignment_reminders();` — rappel push à `response_reminder_hours`, courriel à `response_email_hours`, aux membres actifs dont l'attribution est restée sans réponse *(migration `0021`)* |
| `late_responders_report` | toutes les heures (:45) | `select public.cron_late_responders_report();` — notifie les admins des attributions en attente depuis plus de `late_report_hours`, une fois par jour et par planning, entre 08:00 et 20:59 heure de la caserne *(migration `0021`)* |
| `suspend_subscriptions` | tous les jours 03:30 | `select public.cron_suspend_subscriptions();` — passe en `suspended` les essais expirés sans abonnement et les `past_due` dont la dernière période payée remonte à plus de 14 jours. **Rien n'est supprimé** : la caserne passe en lecture seule via `station_writable()`, et les administrateurs sont prévenus par courriel *(migrations `0023` et `0024`)* |
| `subscription_reminders` | tous les jours 03:20 | `select public.cron_subscription_reminders();` — courriel + notification interne aux administrateurs quand l'essai se termine dans sept jours et qu'aucun abonnement n'a été souscrit *(migration `0024`)* |
| `archive_schedules` | 1er du mois | Archive les plannings des mois passés |
| `prune_notifications` | hebdomadaire | Supprime les notifications lues de plus de 90 jours |

Chaque tâche est un appel **qualifié** (`public.…`) et **sans argument** d'une fonction
`security definer` dont le `search_path` est figé : rien n'est interpolé dans la commande, et
le travail réel se fait dans une fonction que ni `anon` ni `authenticated` ne peuvent appeler.
Toutes les tâches doivent être idempotentes — l'ordonnanceur rejoue après un redémarrage — et
testables sans l'ordonnanceur : leur fonction prend un instant de référence
(`p_reference`, `now()` par défaut) que les tests appellent directement. La CI n'exécute donc
jamais `pg_cron` ; elle vérifie la logique et la présence des lignes dans `cron.job`.

## 9. Index et performance

Les index listés dans les DDL couvrent :
- la grille d'un membre : `availabilities (user_id, date)`,
- la matrice admin : `availabilities (station_id, date)` et `shifts (station_id, date)`,
- l'écran propositions : `assignments (user_id, status)`,
- le centre de notifications : `notifications (user_id) where read_at is null`.

La matrice du ticket 016 n'a demandé **aucun index de plus** : mesurée sur soixante membres,
trente et un jours, deux créneaux et toutes les cellules saisies, `availability_matrix` rend
ses soixante lignes en **~14 ms**, sous le rôle `authenticated` comme sous celui du
propriétaire, et ~20 ms de bout en bout par PostgREST pour 22 ko de réponse
(`supabase/tests/matrice_admin_test.sql § 6`). Ce qui manquait
n'était pas un index mais un **prédicat** : les jointures latérales de `v_member_load` joignent
`shifts` par sa clé primaire et restreignent la date ; sans `s.station_id = p.station_id`, le
planificateur n'a aucune raison de se servir de `shifts (station_id, date)` et parcourt la table
entière, toutes casernes confondues, une fois par membre. Le prédicat est redondant du point de
vue des données (la RLS de `0008` impose déjà la cohérence des `station_id`) et déterminant du
point de vue du plan.

**Le coût dominant n'était ensuite ni un index ni un plan, mais une fonction appelée par
ligne.** `est_jour_ferie` construisait les onze dates de l'année à chaque appel, donc calculait
Pâques trois fois, pour répondre « non » à un mardi de novembre : 30 µs par date, 110 ms pour
3 720 dates, la moitié du coût de la matrice. Réécrite pour tester d'abord les huit fériés
fixes et ne calculer Pâques que dans sa fenêtre (23 mars – 14 juin), elle coûte 6,8 fois moins,
et la matrice est passée de ~25 ms à ~14 ms. La contrepartie — la liste des fériés écrite à
deux endroits — est vérifiée jour par jour de 1900 à 2100 par le test.

**Une mesure se fait sous le rôle de l'application.** `availability_matrix` est
`security definer` : appelée par `postgres`, `auth.uid()` est nul, `is_admin()` répond faux et
la fonction sort en trois millisecondes **par la porte du refus** — chronométrer ce chemin, ce
n'est pas chronométrer une matrice. Le test mesure donc les deux rôles et **exige qu'ils soient
du même ordre** : c'est ce qui attraperait une refonte qui abandonnerait `security definer` et
ferait redescendre la RLS dans la boucle sans qu'aucun test fonctionnel ne bronche.

Trois pistes ont été essayées et **rejetées sur mesure** ; elles n'ont pas à être reprises :
réécrire la fonction en SQL pur (aucun effet — une fonction `security definer` n'est jamais
*inlinée*, le plan reste un `Function Scan` opaque : 23,5 ms contre 26,4 ms) ; forcer un plan
personnalisé (`plan_cache_mode`), le plan générique coûtant déjà la même chose à 266 000 lignes
de disponibilités ; et décomposer le comput de Pâques en fonctions SQL élémentaires
*inlinables*, dont l'expansion combinatoire multiplie le coût par vingt (2 000 ms pour
3 720 appels).

Realtime activé sur `assignments`, `schedules`, `notifications` uniquement, filtré par
`station_id` côté client. **`assignments` y est entrée la première** (migration `0018`,
ticket 017) : deux adjoints qui construisent le même mois doivent voir le travail de l'autre.
**`schedules` a suivi** (migration `0019`, ticket 019) parce que la validation automatique est
un `update` que personne ne déclenche depuis l'écran de suivi : sans ce canal, le chef verrait
les réponses arriver une à une et ne verrait jamais le planning se valider. `notifications`
suivra avec le ticket qui en aura besoin ; `shifts` n'y entrera pas, un changement d'effectif
requis étant un événement rare que « Rafraîchir » rattrape.

Trois vérifications ont conditionné cette inscription, et elles valent pour toute table qu'on
y ajoutera :

1. **Aucun `grant` de colonne restrictif** sur `assignments` : ce que `authenticated` peut lire
   par `select`, il peut le recevoir par ce canal. C'est exactement ce qui manque à
   `invitations` (ci-dessous).
2. **Les événements sont filtrés ligne à ligne** par les politiques de `select` : un membre ne
   reçoit rien d'un planning en brouillon, puisqu'aucune politique ne lui en donne la lecture.
   Le brouillon reste invisible, y compris par ce canal.
3. **L'identité de réplique reste `default`.** La charge utile d'un `delete` n'est pas filtrée
   par les politiques : en `replica identity full`, chaque retrait d'attribution diffuserait
   toutes les colonnes de la ligne supprimée à tous les abonnés. En `default`, il ne diffuse
   que la clé primaire — un `uuid` opaque, sans caserne, sans membre et sans date. Conséquence
   assumée côté client : les attributions y sont indexées par identifiant, seule façon de
   savoir quel créneau redessiner. L'instruction `alter table assignments replica identity
   default` est écrite dans la migration bien qu'elle soit le défaut de PostgreSQL : c'est une
   décision de sécurité, elle doit se voir et être testée
   (`supabase/tests/planning_brouillon_test.sql § 6`).

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
11. `0011_station_settings.sql` (ticket 010 : validation de `settings`, garde-fou de fuseau, `period_deadline_at`, recalcul des dates limites)
12. `0012_cron_periodes.sql` (ticket 014 : `cron_create_periods`, `cron_lock_periods`, `create_period`, transitions et audit des périodes, `set_by` imposé sur `availabilities`, les deux tâches `pg_cron` des périodes)
13. `0013_periodes_completion_audit.sql` (revue du ticket 014 : vue `v_period_completion`, audit de la création et de la suppression d'une période, date limite qui ne recule plus dans le passé)
14. `0014_notifications_envoi.sql` (ticket 025 : `notification_outbox`, `notify`, `notify_post`, `notify_claim`, `notify_complete`, `cron_dispatch_notifications`, secrets Vault et tâche `dispatch_notifications`)
15. ~~`0015_views.sql`~~ — rang resté vide, voir ci-dessous
16. `0016_cron_rappels_saisie.sql` (ticket 015 : `cron_availability_reminders` et la tâche `availability_reminders`)
17. `0017_matrice_admin.sql` (ticket 016 : calendrier français en base, vue `v_member_load`, fonction `availability_matrix`)
18. `0018_planning_brouillon.sql` (ticket 017 : `station_required_count`, `create_schedule`, `assignments_trace_disponibilite`, `assignments_audit_hors_dispo`, suppression d'attribution réservée au brouillon, vue `v_schedule_progress`, inscription d'`assignments` dans `supabase_realtime`)
19. `0019_publication_suivi.sql` (ticket 019 : `schedules_guard_transition`, `schedules_guard_suppression` et `shifts_guard_suppression`, suppression d'un planning et d'un créneau réservée au brouillon, `publish_schedule`, `schedule_complet`, `schedule_reevaluer`, `schedule_auto_validate`, `shifts_effectif_revalide`, `remind_schedule`, inscription de `schedules` dans `supabase_realtime`)
20. `0020_reattribution.sql` (ticket 020 : `assignments_guard_reattribution`, `reassign_shift`, `cancel_assignment`, clause `when` de `schedule_auto_validate` élargie aux acceptations qui disparaissent)
21. `0021_cron_relances.sql` (ticket 022 : `assignment_reminder_targets`, `cron_assignment_reminders`, `cron_late_responders_report`, les deux tâches `pg_cron` des relances)
22. `0022_notification_echec_definitif.sql` (ticket 040 : `notify_trace_echec`, `cron_dispatch_notifications` trace désormais ses abandons)
23. `0023_abonnement_stripe.sql` (ticket 029 : `subscription_bootstrap` et son déclencheur, `subscription_sync`, `subscription_set_customer`, `cron_suspend_subscriptions` et la tâche `suspend_subscriptions`)
24. les tâches d'entretien restantes du § 8, une migration par ticket : `archive_schedules` et
    `prune_notifications`

Les rangs 15 et 16 ont glissé d'un cran au ticket 025 : le chemin d'appel des
notifications devait exister avant les tâches qui s'en servent, et une migration déjà
poussée sur `main` ne se renumérote pas.

**Le rang 15 restera vide.** Il annonçait « les trois vues restantes du § 6 » en un fichier ;
elles appartiennent à trois tickets (016 pour la matrice et `v_member_load`, 017 pour
`v_schedule_progress`), et `0016` a été poussée sur `main` avant que le 016 ne commence.
Intercaler un `0015` après coup donnerait un dépôt dont l'ordre des fichiers n'est plus celui
des applications — la CLI refuserait la migration en retard sur un projet hébergé. Le ticket
016 prend donc le rang `0017`, et `v_schedule_progress` est venue avec les plannings, au
rang `0018`.

Le rang 16 annonçait « les cinq tâches restantes du § 8 » en une migration. Elles
appartiennent à quatre tickets différents : les réunir obligerait soit à écrire du code
sans ticket, soit à modifier plus tard une migration déjà poussée. Le fichier est donc
scindé par sujet au ticket 015, conformément à la règle « une migration par sujet ».

Chaque migration est rejouable sur un projet vide et testée en local avec `supabase start`.

Les politiques RLS sont couvertes par `supabase/tests/rls_test.sql`, exécuté par
`scripts/test_rls.sh` (pas de pgTAP : le script lève une exception et rend un code non nul
dès qu'une politique fuit). Les fonctions d'invitation de `0009` sont couvertes par
`supabase/tests/invitations_test.sql`, et le déclencheur de `0010` par
`supabase/tests/memberships_admin_test.sql`, les paramètres de caserne de `0011` par
`supabase/tests/station_settings_test.sql` le cycle de vie des périodes de `0012` par
`supabase/tests/periods_cron_test.sql` et le chemin d'appel des notifications de `0014`
et `0022` par `supabase/tests/notifications_test.sql`, les rappels de saisie de `0016` par
`supabase/tests/availability_reminders_test.sql`, la matrice de `0017` par
`supabase/tests/matrice_admin_test.sql`, la publication de `0019` par
`supabase/tests/publication_test.sql`, la réattribution de `0020` par
`supabase/tests/reattribution_test.sql` et les relances automatiques de `0021` par
`supabase/tests/assignment_reminders_test.sql`, joués par le même script. La logique pure
des Edge Functions (libellés, regroupement, liens profonds, classement des erreurs FCM,
enchaînement d'un envoi) est couverte par `deno test supabase/functions/tests/`, qui ne
demande ni base ni réseau et tourne en CI. La couche HTTP des Edge
Functions est testée par `scripts/test_functions.sh`, qui a besoin de
`supabase functions serve` et reste donc local : la CI démarre la pile sans `edge-runtime`.

`supabase/types/database.types.ts` est généré par `scripts/gen_types.sh` et versionné
volontairement : les Edge Functions (section 7) l'importent et la CI doit pouvoir les typer sans
base disponible. C'est la seule exception à la règle « pas de fichier généré commité ». Le
régénérer à chaque migration. La CLI ne produit pas de Dart : les modèles Flutter sont écrits à la
main dans `lib/features/<f>/data/` à partir de ce document.
