# Changelog

## 0.1.0 – Stage 1: Base

- Repository, Vite + React 18 + TypeScript (strict) + Tailwind, HashRouter, GitHub Pages deploy workflow, CI workflow.
- Supabase migrations for the full Phase 1 schema (profiles, settings, community list, enrolments, seat holds, payments, refunds, waitlist, mentor assignments, syllabus, chapter progress, study sessions, screen-time reports + private bucket, goals, mentoring sessions, notes, announcements, notifications, audit log, email log).
- Row Level Security on every table with default deny, role helper functions, last-admin and profile-column guards.
- Settings table seeded with all defaults from the brief; audited on change.
- Atomic seat counter and hold creation.
- Auth with email and password, password reset, account invitations (Edge Functions `invite-user`, `request-password-reset`, shared `sendEmail()` helper).
- App shell with role-aware routing and navigation; a minimal home for each of the four roles; invite form for supervisors (mentors) and admins (all roles).
- Seed with labelled test users for each role and clearly labelled sample data (local/test only).
- Tests: 77 database access-rule assertions (pgTAP) and 10 unit tests.
