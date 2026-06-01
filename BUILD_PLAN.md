# FRC Attendance PWA - Build Plan

This is the source of truth for building the app. Build it in phases, in order.
Do not build everything at once. Finish a milestone, commit to git, then stop so I
can test on a real phone before continuing.

## What we're building

A Progressive Web App (PWA) that lets FRC team members check in and out of the
shop using their phone. Primary method is tapping an NFC tag at a door (the tag
opens a check-in URL in the browser). A QR code is an alternate method. An
experimental, optional geofence check verifies the person is near the shop.

Members may check in and out several times a day (e.g. leaving for lunch and
returning). Each tap is its own timestamped event. Daily hours and a season
total are computed by pairing in/out events.

It must work on any phone (iPhone and Android), so we use a URL-based NFC
approach and avoid the Web NFC API (which iOS does not support).

## Tech stack

- Frontend: Vite + React, made installable with `vite-plugin-pwa`
- Backend: Supabase (auth + Postgres database), free tier
- Hosting: Vercel or Netlify, deployed from a GitHub repo
- Auth: magic-link email sign-in as the default (works with school Google
  Workspace email without needing the IT admin to approve a third-party OAuth
  app). Google sign-in can be added later if school IT allowlists the app.

## Conventions (important)

- Work in small increments. Build one milestone, then stop and tell me to test.
- After each milestone works, commit to git with a clear message.
- Keep secrets (Supabase keys) in a `.env` file that is gitignored. I will paste
  in my own keys; never hardcode them.
- Deploy early and re-deploy often so I can test on real phones. NFC and "add to
  home screen" do not work on a desktop browser.
- Keep persistent login so a member is not asked to log in on every tap.

## Data model (Supabase / Postgres)

`profiles`
- id (uuid, references auth.users)
- full_name (text)
- role (text: 'student' or 'mentor')

`attendance_events`
- id (uuid)
- user_id (uuid, references profiles.id)
- event_time (timestamptz, default now())
- type (text: 'in' or 'out')
- location (text, e.g. 'main-door', 'side-door')
- method (text: 'nfc', 'qr', or 'geofence')
- lat (float, nullable)
- lng (float, nullable)
- verified (boolean, whether a location check passed)

Daily hours = sum of the time between each paired 'in' and 'out' for a user on a
given day. A member's current status is 'in' if their most recent event today is
'in', otherwise 'out'.

## Phase 1: the thin vertical slice (get this fully working first)

Milestone 1 - Installable shell
- Scaffold a Vite + React app and add `vite-plugin-pwa`.
- Deploy it so I get a live URL.
- Goal: I can open the URL on my iPhone and Android and "Add to Home Screen,"
  and it launches like an app. It does not need to do anything yet.
- Stop. I will test, then tell you to continue.

Milestone 2 - Login that sticks
- Connect Supabase. Implement magic-link email sign-in.
- Keep the session persistent across app restarts.
- Goal: I can log in once with my email and stay logged in after closing and
  reopening the app.
- Stop and let me test.

Milestone 3 - The check-in route
- Create a route `/checkin` that reads a `loc` query parameter
  (e.g. `/checkin?loc=main-door`).
- When a logged-in member visits it, record an `attendance_events` row for that
  member: set `type` by toggling from their last event (default 'in' if none
  today), set `location` from `loc`, set `method` to 'nfc'.
- Show a clear confirmation ("Checked in at 4:12 PM at main-door").
- Goal: typing `/checkin?loc=main-door` in my phone browser records an event.
  No NFC hardware yet.
- Stop and let me test.

Milestone 4 - Status screen
- The home screen shows current status (checked in since X, or not checked in),
  today's list of in/out events, and hours for today plus a season total.
- A big check in / check out button that toggles, for use without a tag.
- Stop and let me test.

When Phase 1 works end to end, the core of the app is done.

## Phase 2: physical NFC tags

- I will buy NTAG213 stickers (use "on-metal" tags for metal door frames) and
  write each one with a check-in URL using the free "NFC Tools" phone app, e.g.
  `https://OURDOMAIN/checkin?loc=main-door`, `?loc=side-door`, etc.
- One tag per entrance, each with a different `loc` value, all pointing at the
  same app.
- Help me confirm the tap works on both an iPhone and an Android.

## Phase 3: later features (do not build yet)

- QR code alternate: a `/checkin` link encoded as a printed QR at each door.
- Experimental geofence: on the `/checkin` route, optionally read the browser
  geolocation and set `verified` based on distance from the shop coordinates.
  Make this a toggle, not the primary method.
- Mentor dashboard: who is currently in, attendance history, total hours per
  member, flags for anyone who forgot to check out.
- Whatever other team features come next.

## Setup checklist for me (the human)

- [ ] Ask school IT whether students can use their school Google account with an
      outside app. If not, we stay on magic-link email login.
- [ ] Create a free Supabase account and a new project; copy the project URL and
      anon key for the `.env` file.
- [ ] Create a GitHub repo for the project.
- [ ] Create a Vercel or Netlify account and connect the repo for deploys.
- [ ] Buy a small pack of NTAG213 NFC tags (and on-metal tags if door frames are
      metal).
