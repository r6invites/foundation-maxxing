# Decisions

One line of reasoning per non-trivial assumption. Newest stage last.

## Stage 1

1. **HashRouter + `token_hash` email links.** Supabase's default email redirects put tokens in the URL fragment, which collides with hash routing. Our Edge Functions generate the link ourselves (`#/auth/confirm?token_hash=…&type=recovery`) and the app exchanges it with `verifyOtp`; `detectSessionInUrl` is off. Also avoids redirect allow-list setup.
2. **Role comes only from `raw_app_meta_data`.** `raw_user_meta_data` is editable by the visitor at sign-up, so trusting it would let anyone become an admin. A pgTAP test covers this.
3. **Public sign-up is disabled.** Students will register through an Edge Function (Stage 2a) after the community check; staff are invited. A dashboard sign-up would bypass both.
4. **Invitations and password resets use `createUser`/`generateLink` + `sendEmail()`.** Supabase's own mailer would bypass the "email only from Edge Functions via one helper" rule. Invitations are all-or-nothing: if the email fails the new account is deleted.
5. **Password reset always answers "ok", limited to 5 emails per address per hour** (counted in `email_log`) so it cannot be used to discover accounts or spam an inbox. Response timing can still differ slightly; accepted for Phase 1.
6. **One `enrollments` row per student** (unique `student_id`); status changes over time and a renewal updates cycle dates on the same row. The pre-payment state is a seat hold with no enrolment row, so the brief's seven statuses are kept unchanged.
7. **Seat count follows the brief literally:** `awaiting_approval` + `active` + unexpired holds. A student in `payment_due` (grace period) does **not** currently hold a seat. See the open question in the Stage 1 report.
8. **Seat hold and capacity check are one SQL function** (`create_seat_hold`) using a transaction advisory lock; callable only by the service role. `seats_left()` never goes negative if capacity is lowered.
9. **Browser cannot write payments, enrolments, holds, refunds or notifications.** Only read policies exist; writes happen in Edge Functions with the service role after server-side checks.
10. **Settings are readable by any active signed-in user** (they hold no secrets and the app needs them) and writable by admins only. Signed-out pages read a fixed whitelist through `public_settings()`. Every settings change is audited by a database trigger so no code path can skip it.
11. **Audit log is append-only** (update/delete blocked by trigger, even for the database owner) and writable only via `write_audit()` (service role) or triggers.
12. **Profile column guard.** Ordinary users can edit only name, city, attempt and guardian fields. Role, active flag, email, phone, date of birth and consent fields change only through admins or the service role. Email changes arrive in Stage 2a with the profile screen.
13. **Last-admin protection is a database trigger**, so it holds for every route including direct SQL and cascades.
14. **Deactivated users can read nothing**: every policy goes through `auth_role()`, which returns null for inactive profiles, including the user's own profile row (found by a failing test). The Edge Function that deactivates (Stage 2b) will also ban the auth user so tokens stop refreshing.
15. **Study-session UPDATE policy lets a student always edit their own *running* session** (to pause/stop) and a finished one only within 24 hours. Server-side functions will tighten what fields can change in Stage 2d.
16. **Goals:** one row per student (a goal "for many students" is many rows). Students may only toggle Pending / In progress; every status or period change is written to `goal_history` by trigger.
17. **Session notes:** versions are written by trigger on every edit; no delete policy exists, so nobody can delete a saved note. Supervisors and admins read only.
18. **Screenshots:** private bucket `screen-time`, 2 MB limit and image MIME types enforced by the bucket, objects stored at `<student_id>/<file>`, read policy reuses `can_view_student`.
19. **Vite `base` defaults to `./`** (relative assets), which works at a repo sub-path and a root domain without configuration; `VITE_BASE_PATH` overrides it. CI sets it to `/<repo name>/`.
20. **Minimum password length 10** (config.toml and the forms). Hard session time-limits are a paid Supabase feature; sessions currently expire via the 1-hour access token plus refresh. See question in report if a hard cap is needed.
21. **Dependencies are added when first used.** Recharts is not installed yet (first chart is Stage 2d). No ESLint in Stage 1; strictness comes from `tsc` with `noUnusedLocals`, `noUnusedParameters`, `noUncheckedIndexedAccess`.
22. **Verification environment.** Migrations, seed and the access-rule tests were run against plain PostgreSQL 16 with minimal stand-ins for Supabase's `auth` and `storage` schemas, and Edge Functions were type-checked with Deno. The full Supabase stack could not run in the build sandbox (no Docker daemon), so `ci.yml` runs `supabase test db` on a real stack.
23. **Phone numbers:** normalised to E.164 in the database (`normalize_phone`) so every entry path agrees; invalid numbers are rejected rather than guessed.
