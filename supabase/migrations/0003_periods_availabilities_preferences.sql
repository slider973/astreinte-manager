-- 0003 — periods, availabilities, availability_preferences.
-- Référence : docs/SCHEMA.md sections 2.5, 2.6 et 2.7.

-- ---------------------------------------------------------------------------
-- 2.5 periods — un mois de saisie par caserne
-- ---------------------------------------------------------------------------
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

comment on table periods is
  'Mois de saisie des disponibilités. Créée pour M+1 et M+2 (cron ou admin). deadline_at calculée depuis settings.availability_deadline_day dans le fuseau de la caserne.';

create trigger periods_set_updated_at
  before update on periods
  for each row execute function set_updated_at();

alter table periods enable row level security;

-- ---------------------------------------------------------------------------
-- 2.6 availabilities
-- ---------------------------------------------------------------------------
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

comment on table availabilities is
  'Disponibilité d''un membre pour un créneau. Absence de ligne = non saisi. L''app écrit par upsert et supprime pour décocher.';

create trigger availabilities_set_updated_at
  before update on availabilities
  for each row execute function set_updated_at();

alter table availabilities enable row level security;

-- ---------------------------------------------------------------------------
-- 2.7 availability_preferences — quotas par membre et par mois
-- ---------------------------------------------------------------------------
create table availability_preferences (
  id            uuid primary key default gen_random_uuid(),
  station_id    uuid not null references stations(id) on delete cascade,
  user_id       uuid not null references profiles(id) on delete cascade,
  period_id     uuid not null references periods(id) on delete cascade,
  max_shifts    int check (max_shifts is null or max_shifts >= 0),     -- null = illimité
  max_weekends  int check (max_weekends is null or max_weekends >= 0), -- null = illimité
  comment       text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (station_id, user_id, period_id)
);

comment on table availability_preferences is 'Quotas déclarés par un membre pour une période (null = illimité).';

create trigger availability_preferences_set_updated_at
  before update on availability_preferences
  for each row execute function set_updated_at();

alter table availability_preferences enable row level security;
