-- ─────────────────────────────────────────────────────────────────────────────
-- Forgotten-checkout handling
-- Run once in the Supabase SQL editor.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Configurable key/value settings store
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists app_settings (
  key        text primary key,
  value      text not null,
  updated_at timestamptz default now()
);

insert into app_settings (key, value)
values ('auto_close_cutoff', '22:00')   -- default 10:00 PM America/Los_Angeles
on conflict (key) do nothing;

alter table app_settings enable row level security;

drop policy if exists "authenticated can read settings"  on app_settings;
drop policy if exists "staff can update settings"        on app_settings;

create policy "authenticated can read settings"
  on app_settings for select to authenticated using (true);

create policy "staff can update settings"
  on app_settings for update to authenticated
  using (
    exists (
      select 1 from member_roles
      where member_id = auth.uid()
        and role in ('mentor', 'lead', 'admin')
    )
  )
  with check (
    exists (
      select 1 from member_roles
      where member_id = auth.uid()
        and role in ('mentor', 'lead', 'admin')
    )
  );


-- 2. Session review table
--    One row per auto-closed session.  status: pending → approved | voided.
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists session_reviews (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id)      on delete cascade not null,
  checkin_id  uuid references attendance_events(id) on delete cascade not null unique,
  checkout_id uuid references attendance_events(id) on delete cascade not null unique,
  status      text not null default 'pending'
                check (status in ('pending', 'approved', 'voided')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at  timestamptz default now()
);

create index if not exists session_reviews_user_id_idx    on session_reviews(user_id);
create index if not exists session_reviews_checkout_id_idx on session_reviews(checkout_id);

alter table session_reviews enable row level security;

drop policy if exists "authenticated can read session_reviews" on session_reviews;
drop policy if exists "staff can update session_reviews"       on session_reviews;

create policy "authenticated can read session_reviews"
  on session_reviews for select to authenticated using (true);

create policy "staff can update session_reviews"
  on session_reviews for update to authenticated
  using (
    exists (
      select 1 from member_roles
      where member_id = auth.uid()
        and role in ('mentor', 'lead', 'admin')
    )
  )
  with check (
    exists (
      select 1 from member_roles
      where member_id = auth.uid()
        and role in ('mentor', 'lead', 'admin')
    )
  );


-- 3. Auto-close function
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function auto_close_open_checkins()
returns int language plpgsql security definer set search_path = public as $$
declare
  cutoff_str   text;
  cutoff_ts    timestamptz;
  rec          record;
  new_checkout uuid;
  closed_count int := 0;
begin
  -- Read the configurable cutoff (stored as 'HH:MM', local = America/Los_Angeles)
  select value into cutoff_str
  from app_settings where key = 'auto_close_cutoff';
  cutoff_str := coalesce(cutoff_str, '22:00');

  -- Cutoff timestamp for today in LA time
  cutoff_ts := timezone('America/Los_Angeles',
    (current_date::text || ' ' || cutoff_str)::timestamp);

  -- If we're before today's cutoff (e.g. a manual test run mid-day), step back one day
  if now() < cutoff_ts then
    cutoff_ts := cutoff_ts - interval '1 day';
  end if;

  -- Find every check-in that:
  --   • falls inside the 24-hour window that ended at the cutoff
  --   • has no checkout event at any later time
  --   • has not already been auto-closed (no existing session_review row)
  for rec in
    select ae.id as checkin_id, ae.user_id
    from attendance_events ae
    where ae.type = 'in'
      and ae.event_time >= cutoff_ts - interval '24 hours'
      and ae.event_time <  cutoff_ts
      and not exists (
        select 1 from attendance_events ao
        where ao.user_id  = ae.user_id
          and ao.type     = 'out'
          and ao.event_time > ae.event_time
      )
      and not exists (
        select 1 from session_reviews sr
        where sr.checkin_id = ae.id
      )
  loop
    -- Insert the synthetic checkout stamped exactly at the cutoff time
    insert into attendance_events (user_id, type, event_time, location, method)
    values (rec.user_id, 'out', cutoff_ts, 'auto', 'auto_close')
    returning id into new_checkout;

    -- Create the review record
    insert into session_reviews (user_id, checkin_id, checkout_id, status)
    values (rec.user_id, rec.checkin_id, new_checkout, 'pending');

    closed_count := closed_count + 1;
  end loop;

  return closed_count;
end;
$$;


-- 4. Schedule with pg_cron
-- ─────────────────────────────────────────────────────────────────────────────
-- Runs at 08:00 UTC daily, which is midnight PST (UTC-8) / 01:00 AM PDT (UTC-7).
-- This is safely past the default 10 PM cutoff for any US Pacific time.
--
-- If you move the cutoff to 11:30 PM or later, shift this schedule to 09:00 UTC
-- to stay comfortably after it.
--
-- The function itself reads the current cutoff from app_settings on every run,
-- so changing the setting takes effect without re-scheduling the cron job
-- (as long as it stays before 08:00 UTC / midnight Pacific).

select cron.schedule(
  'auto-close-checkins',    -- unique job name; run again to update
  '0 8 * * *',             -- 08:00 UTC every day
  $$select auto_close_open_checkins()$$
);

-- To update the cutoff time later (e.g. for late build season):
--   update app_settings set value = '23:30', updated_at = now()
--   where key = 'auto_close_cutoff';
--
-- To view or manage cron jobs:
--   select * from cron.job;
--   select cron.unschedule('auto-close-checkins');
