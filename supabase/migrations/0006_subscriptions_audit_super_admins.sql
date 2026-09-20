-- 0006 — subscriptions, audit_log, super_admins.
-- Référence : docs/SCHEMA.md sections 2.13, 2.14 et 2.15.

-- ---------------------------------------------------------------------------
-- 2.13 subscriptions
-- ---------------------------------------------------------------------------
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

comment on table subscriptions is 'Abonnement Stripe d''une caserne. Écrit uniquement par le webhook Stripe (service role).';

create trigger subscriptions_set_updated_at
  before update on subscriptions
  for each row execute function set_updated_at();

alter table subscriptions enable row level security;

-- ---------------------------------------------------------------------------
-- 2.14 audit_log
-- ---------------------------------------------------------------------------
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

comment on table audit_log is 'Journal des actions sensibles des admins, alimenté par triggers et service role.';

alter table audit_log enable row level security;

-- ---------------------------------------------------------------------------
-- 2.15 super_admins
-- ---------------------------------------------------------------------------
create table super_admins (
  user_id       uuid primary key references profiles(id) on delete cascade,
  created_at    timestamptz not null default now()
);

comment on table super_admins is 'Opérateurs de la plateforme. Alimentée en SQL manuel uniquement.';

alter table super_admins enable row level security;
