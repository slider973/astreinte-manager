-- 0001 — Extensions, enums et table stations.
-- Référence : docs/SCHEMA.md sections 1, 2.1 et 5.
-- Rejouable sur un projet vide. Pas de politique RLS ici (ticket 008), mais RLS activé.

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
-- pgcrypto : gen_random_bytes pour les tokens d'invitation, crypt() pour le seed.
-- pg_cron / pg_net : tâches planifiées (ticket 022) et appels HTTP vers les Edge
-- Functions (ticket 025). Activés dès maintenant pour que le projet distant et le
-- local aient la même base.
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_net;
create extension if not exists pg_cron;

-- Sur un projet Supabase hébergé, le schéma cron appartient à supabase_admin et
-- l'event trigger issue_pg_cron_access donne déjà les droits au rôle postgres :
-- ces grants y échoueraient. Ils ne servent qu'en local, d'où le garde-fou.
do $$
begin
  grant usage on schema cron to postgres;
  grant all privileges on all tables in schema cron to postgres;
exception
  when insufficient_privilege then null;
end $$;

-- ---------------------------------------------------------------------------
-- Enums (docs/SCHEMA.md section 1)
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Trigger générique updated_at (docs/SCHEMA.md section 5)
-- ---------------------------------------------------------------------------
create function set_updated_at() returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function set_updated_at() is
  'Met à jour updated_at à chaque update. Posé sur toutes les tables ayant cette colonne.';

-- ---------------------------------------------------------------------------
-- 2.1 stations — casernes
-- ---------------------------------------------------------------------------
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

comment on table stations is 'Casernes (centres de secours). Une ligne par client.';
comment on column stations.settings is
  'Réglages validés côté Edge Function et app : day_start, day_end, required_day, required_night, required_overrides, availability_deadline_day, response_reminder_hours, response_email_hours, late_report_hours.';

create trigger stations_set_updated_at
  before update on stations
  for each row execute function set_updated_at();

alter table stations enable row level security;
