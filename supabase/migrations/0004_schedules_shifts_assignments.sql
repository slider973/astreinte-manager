-- 0004 — schedules, shifts, assignments.
-- Référence : docs/SCHEMA.md sections 2.8, 2.9 et 2.10.
-- Le trigger assignments_member_transition (section 4) arrive avec les RLS (ticket 008),
-- schedule_auto_validate et audit_admin_actions avec les tickets 019/025.

-- ---------------------------------------------------------------------------
-- 2.8 schedules — un planning par caserne et par mois
-- ---------------------------------------------------------------------------
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

comment on table schedules is 'Planning d''astreinte d''une caserne pour une période. Un seul par (caserne, période).';

create trigger schedules_set_updated_at
  before update on schedules
  for each row execute function set_updated_at();

alter table schedules enable row level security;

-- ---------------------------------------------------------------------------
-- 2.9 shifts — créneaux à pourvoir
-- ---------------------------------------------------------------------------
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

comment on table shifts is
  'Créneaux (jour × slot) d''un planning, générés à sa création avec required_count déduit des settings.';

create trigger shifts_set_updated_at
  before update on shifts
  for each row execute function set_updated_at();

alter table shifts enable row level security;

-- ---------------------------------------------------------------------------
-- 2.10 assignments — attribution d'un membre à un créneau
-- ---------------------------------------------------------------------------
create table assignments (
  id               uuid primary key default gen_random_uuid(),
  station_id       uuid not null references stations(id) on delete cascade,
  shift_id         uuid not null references shifts(id) on delete cascade,
  user_id          uuid not null references profiles(id) on delete cascade,
  status           assignment_status not null default 'proposed',
  was_available    boolean not null default true,  -- false si attribué hors disponibilité
  proposed_at      timestamptz,                    -- renseigné à la publication
  responded_at     timestamptz,
  decline_reason   text,
  replaced_by      uuid references assignments(id),
  reminder_count   int not null default 0,
  last_reminder_at timestamptz,
  created_by       uuid not null references profiles(id),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create unique index assignments_active_uniq
  on assignments (shift_id, user_id)
  where status in ('proposed', 'accepted');
create index on assignments (user_id, status);
create index on assignments (station_id, status);

comment on table assignments is
  'Attribution d''un membre à un créneau. Une seule attribution active (proposed/accepted) par (créneau, membre) ; les autres statuts restent pour l''historique.';

create trigger assignments_set_updated_at
  before update on assignments
  for each row execute function set_updated_at();

alter table assignments enable row level security;
