-- 0005 — push_tokens, notifications.
-- Référence : docs/SCHEMA.md sections 2.11 et 2.12. Aucune colonne updated_at ici.

-- ---------------------------------------------------------------------------
-- 2.11 push_tokens
-- ---------------------------------------------------------------------------
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

comment on table push_tokens is 'Tokens FCM par appareil. Un token invalide renvoyé par FCM est supprimé par l''Edge Function d''envoi.';

alter table push_tokens enable row level security;

-- ---------------------------------------------------------------------------
-- 2.12 notifications — journal et centre de notifications
-- ---------------------------------------------------------------------------
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

comment on table notifications is
  'Une ligne inapp par événement alimente le centre de notifications ; les lignes push et email tracent les envois.';

alter table notifications enable row level security;
