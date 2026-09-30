-- Planning fictif des captures du site vitrine (ticket 075), joué le 30 septembre 2026 sur la
-- base LOCALE après `supabase db reset`. Jamais sur la production. Dates en dur : octobre 2026.
-- Retouches faites ensuite à la main : le créneau du 14 de Marie passé en `accepted`,
-- `proposed_at` et `published_at` reculés d'un jour (l'app affiche « Hier »).

begin;
-- L'admin Jean Dupont, pour is_admin() dans create_schedule.
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-4000-8000-000000000100","role":"authenticated"}', true);

do $$
declare
  st   constant uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
  per  constant uuid := 'aaaaaaaa-0000-4000-8000-000000000201';
  adm  constant uuid := 'aaaaaaaa-0000-4000-8000-000000000100';
  marie constant uuid := 'aaaaaaaa-0000-4000-8000-000000000101';
  sch  uuid;
  sh   record;
  cand record;
  res  jsonb;
begin
  sch := (create_schedule(st, per)).id;

  -- Marie d'abord : 1er nuit, 3 jour (samedi), 5 jour, 14 jour.
  res := apply_auto_proposal(sch, adm, (
    select jsonb_agg(jsonb_build_object('shift_id', s.id, 'user_id', marie))
    from shifts s where s.schedule_id = sch
      and (s.date, s.slot) in (('2026-10-01'::date,'night'::slot_type),('2026-10-03','day'),('2026-10-05','day'),('2026-10-14','day'))));
  raise notice 'Marie: %', res;

  -- Puis chaque créneau restant : le candidat disponible le moins chargé.
  for sh in select s.* from shifts s where s.schedule_id = sch order by s.date, s.slot loop
    for cand in
      select a.user_id
      from availabilities a
      join memberships m on m.user_id = a.user_id and m.station_id = st and m.role = 'member'
      where a.station_id = st and a.date = sh.date and a.slot = sh.slot and a.status = 'available'
        and a.user_id <> marie
      order by (select count(*) from assignments x join shifts y on y.id = x.shift_id
                where x.user_id = a.user_id and y.schedule_id = sch), a.user_id
    loop
      exit when (select count(*) from assignments x where x.shift_id = sh.id and x.status in ('proposed','accepted')) >= sh.required_count;
      perform apply_auto_proposal(sch, adm, jsonb_build_array(jsonb_build_object('shift_id', sh.id, 'user_id', cand.user_id)));
    end loop;
  end loop;

  res := publish_schedule(sch, adm);
  raise notice 'publish: ok=% status=% assignments=%', res->'ok', res->'status', res->'assignments';

  -- Réponses : la plupart acceptées. Restent proposées : les 3 de Marie après le 1er,
  -- et une par membre 2..6 dans la seconde quinzaine.
  update assignments a set status = 'accepted', responded_at = now() - interval '2 days'
  from shifts s
  where s.id = a.shift_id and s.schedule_id = sch and a.status = 'proposed'
    and not (a.user_id = marie and s.date > '2026-10-01')
    and a.id not in (
      select distinct on (a2.user_id) a2.id from assignments a2 join shifts s2 on s2.id = a2.shift_id
      where s2.schedule_id = sch and s2.date >= '2026-10-18' and a2.user_id <> marie
        and a2.user_id in ('aaaaaaaa-0000-4000-8000-000000000102','aaaaaaaa-0000-4000-8000-000000000103',
                           'aaaaaaaa-0000-4000-8000-000000000104','aaaaaaaa-0000-4000-8000-000000000105',
                           'aaaaaaaa-0000-4000-8000-000000000106')
      order by a2.user_id, s2.date desc);
end $$;
commit;

select s.status, count(*) filter (where a.status='accepted') acc, count(*) filter (where a.status='proposed') prop,
  (select count(*) from shifts where schedule_id = s.id) creneaux,
  (select count(*) from shifts sh where sh.schedule_id = s.id and not exists (select 1 from assignments z where z.shift_id = sh.id and z.status in ('proposed','accepted'))) vides
from schedules s join shifts sh on sh.schedule_id = s.id join assignments a on a.shift_id = sh.id group by s.id, s.status;
select p.first_name, sh.date, sh.slot, a.status from assignments a join shifts sh on sh.id=a.shift_id join profiles p on p.id=a.user_id where a.user_id='aaaaaaaa-0000-4000-8000-000000000101' order by sh.date;
