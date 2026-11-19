# Foundation Maxxing

Paid private mentoring platform for CA Foundation students, run by the community "CA Foundation Connect".
Students pay monthly, a supervisor approves them, and mentors guide them. This repository is **Phase 1, Stage 1 (Base)**.
See `CHANGELOG.md` for what exists, `DECISIONS.md` for assumptions, and the build brief for the full scope.

## Stack

React 18 + TypeScript (strict) + Vite + Tailwind, HashRouter, TanStack Query, React Hook Form + Zod, date-fns (India time).
Backend: Supabase (Postgres, Auth, Row Level Security, Edge Functions, storage). Hosting: GitHub Pages. Email: Resend (only from Edge Functions). Payments: Razorpay (Stage 2a).

## Folder layout

```
src/                    React app
  auth/                 AuthProvider, role route guard
  components/           Layout, forms, feedback components
  hooks/                useBranding (program name from the database)
  lib/                  supabase client, roles, India-time formatting, Edge Function calls
  pages/                Sign-in, password screens, one minimal home per role
supabase/
  migrations/           All schema, RLS policies and functions (versioned SQL)
  functions/            Edge Functions (+ _shared helpers incl. sendEmail)
  tests/database/       pgTAP access-rule tests
  seed.sql              LOCAL/TEST ONLY labelled accounts and sample data
  config.toml           Local stack settings
.github/workflows/      deploy.yml (GitHub Pages), ci.yml (checks on branches/PRs)
```

## Environment variables

| Where | Name | Purpose |
| --- | --- | --- |
| Frontend build | `VITE_SUPABASE_URL` | Supabase project URL (public) |
| Frontend build | `VITE_SUPABASE_ANON_KEY` | Supabase anon key (public by design) |
| Frontend build | `VITE_BASE_PATH` | Optional. `/repo-name/` for GitHub Pages sub-path, `/` for a custom root domain. Unset = relative assets, works anywhere |
| Supabase secret | `APP_URL` | Full site address, e.g. `https://<owner>.github.io/<repo>/`. Used to build email links and for CORS |
| Supabase secret | `RESEND_API_KEY` | Email provider key |
| Supabase secret | `EMAIL_FROM` | Sender, e.g. `Foundation Maxxing <hello@your-domain>` (domain verified in Resend) |

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided to Edge Functions automatically. **Never** put a secret in the repo or in a `VITE_` variable: everything with that prefix ends up in the browser.

## Run locally

Prerequisites: Node 20+, Docker, the [Supabase CLI](https://supabase.com/docs/guides/cli).

```bash
npm install
supabase start                 # applies migrations and supabase/seed.sql
cp .env.example .env.local     # paste the API URL and anon key printed by `supabase start`
npm run dev                    # http://localhost:5173
```

To try Edge Functions locally create `supabase/functions/.env` (git-ignored) with `APP_URL=http://localhost:5173/`, `RESEND_API_KEY`, `EMAIL_FROM`, then `supabase functions serve --env-file supabase/functions/.env`.

### Test accounts (local/test only, from `seed.sql`)

Password for all: `TestPass#2026`

| Email | Role | Notes |
| --- | --- | --- |
| admin.test@fm-test.example | Admin | |
| supervisor.test@fm-test.example | Supervisor | |
| mentor1.test@fm-test.example | Mentor | assigned to Student One |
| mentor2.test@fm-test.example | Mentor | no students |
| student1.test@fm-test.example | Student | has Mentor One |
| student2.test@fm-test.example | Student | no mentor (use to prove mentors cannot see unassigned students) |

These emails are not real mailboxes, so reset and invitation emails to them are not delivered. **Never run `seed.sql` against production.**

## Tests

```bash
npm run typecheck     # TypeScript strict
npm test              # unit tests (roles, India-time formatting)
supabase start && npm run test:db   # pgTAP access-rule tests (needs the local stack)
```

## Deploy

### Database and functions (per environment: test, then production)

```bash
supabase link --project-ref <ref>
supabase db push                                   # migrations only; seed is NOT applied
supabase secrets set APP_URL=... RESEND_API_KEY=... EMAIL_FROM=...
supabase functions deploy invite-user
supabase functions deploy request-password-reset --no-verify-jwt
```

Supabase dashboard settings to match `supabase/config.toml` (Authentication):
- **Sign-ups disabled** (visitors must not create accounts directly).
- Minimum password length **10**.
- Site URL = the deployed site address.
- The first admin: create the user in Authentication > Users, then run in the SQL editor
  `update public.profiles set role = 'admin' where email = '<their email>';`
  (the database allows this because it runs without a signed-in user).

### Website (GitHub Pages)

1. Repository **Settings > Pages > Source: GitHub Actions**.
2. **Settings > Secrets and variables > Actions > Variables**: add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`. Optionally `VITE_BASE_PATH` (default is `/<repository name>/`, so a repo rename or transfer needs no change; for a custom root domain set it to `/`).
3. Push to `main`. `deploy.yml` type-checks, tests, builds and publishes.

### Moving to another repository later

Push the full history to the new repo, redo the Pages settings and variables above, update the Supabase secret `APP_URL` and the Supabase Site URL to the new address. No code changes.

## Security notes

- Row Level Security is on for every table with default deny; each policy has a comment in the migration saying who may do what.
- Money, enrolment status and seat holds are not writable from the browser at all; only Edge Functions with the service role change them.
- The role of a new account comes only from server-controlled `app_metadata`, never from anything a visitor can type.
