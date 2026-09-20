-- 0002 — profiles, memberships, invitations et trigger handle_new_user.
-- Référence : docs/SCHEMA.md sections 2.2, 2.3, 2.4 et 5.

-- ---------------------------------------------------------------------------
-- 2.2 profiles — extension de auth.users
-- ---------------------------------------------------------------------------
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

comment on table profiles is
  'Profil applicatif, créé par trigger à l''inscription. email dupliqué depuis auth.users pour les jointures.';

create trigger profiles_set_updated_at
  before update on profiles
  for each row execute function set_updated_at();

alter table profiles enable row level security;

-- Trigger sur auth.users : crée la ligne profiles à l'inscription.
-- first_name / last_name sont lus dans raw_user_meta_data s'ils sont fournis
-- (signUp avec `data: {first_name, last_name}`), sinon chaîne vide.
create function handle_new_user() returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into profiles (id, email, first_name, last_name)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'first_name', ''),
    coalesce(new.raw_user_meta_data ->> 'last_name', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

comment on function handle_new_user() is
  'Crée la ligne profiles correspondant à un nouvel utilisateur auth.users.';

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ---------------------------------------------------------------------------
-- 2.3 memberships — appartenance à une caserne
-- ---------------------------------------------------------------------------
create table memberships (
  id            uuid primary key default gen_random_uuid(),
  station_id    uuid not null references stations(id) on delete cascade,
  user_id       uuid not null references profiles(id) on delete cascade,
  role          membership_role not null default 'member',
  status        membership_status not null default 'active',
  display_name  text,                          -- surnom ou nom court affiché dans la caserne
  skills        text[] not null default '{}',  -- réservé v1.1 (chef d'agrès, conducteur...)
  joined_at     timestamptz not null default now(),
  disabled_at   timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (station_id, user_id)
);
create index on memberships (user_id);
create index on memberships (station_id, status);

comment on table memberships is 'Appartenance d''un utilisateur à une caserne, avec son rôle.';

create trigger memberships_set_updated_at
  before update on memberships
  for each row execute function set_updated_at();

alter table memberships enable row level security;

-- ---------------------------------------------------------------------------
-- 2.4 invitations
-- ---------------------------------------------------------------------------
create table invitations (
  id            uuid primary key default gen_random_uuid(),
  station_id    uuid not null references stations(id) on delete cascade,
  email         text not null,
  role          membership_role not null default 'member',
  token         text not null unique default encode(extensions.gen_random_bytes(24), 'hex'),
  invited_by    uuid not null references profiles(id),
  expires_at    timestamptz not null default now() + interval '14 days',
  accepted_at   timestamptz,
  created_at    timestamptz not null default now()
);
create unique index invitations_pending_uniq
  on invitations (station_id, lower(email)) where accepted_at is null;

comment on table invitations is 'Invitations envoyées par un admin. Une seule invitation en attente par (caserne, email).';

alter table invitations enable row level security;
