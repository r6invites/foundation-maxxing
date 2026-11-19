-- =====================================================================
-- 0001 core: enums, helper functions, profiles, settings, community list
-- All tables use Row Level Security with default deny. Each policy has a
-- comment saying who may do what.
-- =====================================================================

-- ---------- enums ----------
create type public.user_role as enum ('student', 'mentor', 'supervisor', 'admin');

create type public.enrollment_status as enum (
  'awaiting_approval', 'active', 'payment_due', 'lapsed',
  'refund_requested', 'left', 'rejected'
);

create type public.payment_kind   as enum ('online', 'manual');
create type public.payment_status as enum ('created', 'paid', 'failed', 'refunded');
create type public.refund_kind    as enum ('student_request', 'registration_rejected');
create type public.refund_status  as enum ('requested', 'approved', 'refunded', 'rejected');
create type public.hold_status    as enum ('active', 'converted', 'released');
create type public.waitlist_status as enum ('waiting', 'offered', 'converted', 'expired', 'removed');
create type public.syllabus_level as enum ('paper', 'chapter', 'sub_chapter', 'topic');
create type public.topic_status   as enum ('pending', 'studied', 'verified');
create type public.study_source   as enum ('stopwatch', 'timer', 'manual');
create type public.goal_period    as enum ('weekly', 'monthly');
create type public.goal_status    as enum ('pending', 'in_progress', 'done', 'missed', 'rescheduled');
create type public.session_mode   as enum ('online', 'in_person');
create type public.session_status as enum ('scheduled', 'completed', 'missed', 'cancelled', 'rescheduled');
create type public.note_visibility as enum ('private', 'mentors', 'student');
create type public.announcement_audience as enum ('students', 'mentors', 'both');

-- ---------- generic helpers ----------
create function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Normalise an Indian phone number to E.164 (+91XXXXXXXXXX).
-- Strips spaces, dashes, brackets, dots; drops a leading 0 or 91 / +91.
-- Returns null for empty input and raises for anything that is not 10 digits afterwards.
create function public.normalize_phone(p text) returns text
language plpgsql immutable as $$
declare
  digits text;
begin
  if p is null or btrim(p) = '' then
    return null;
  end if;
  digits := regexp_replace(p, '[^0-9]', '', 'g');
  if length(digits) = 12 and left(digits, 2) = '91' then
    digits := substr(digits, 3);
  elsif length(digits) = 11 and left(digits, 1) = '0' then
    digits := substr(digits, 2);
  end if;
  if digits !~ '^[6-9][0-9]{9}$' then
    raise exception 'Invalid Indian mobile number' using errcode = '22023';
  end if;
  return '+91' || digits;
end;
$$;

-- ---------- profiles ----------
create table public.profiles (
  id               uuid primary key references auth.users (id) on delete cascade,
  role             public.user_role not null default 'student',
  full_name        text not null default '',
  email            text not null,
  phone            text unique check (phone is null or phone ~ '^\+91[6-9][0-9]{9}$'),
  date_of_birth    date,
  city             text,
  attempt_month    smallint check (attempt_month between 1 and 12),
  attempt_year     smallint check (attempt_year between 2020 and 2100),
  guardian_name    text,
  guardian_phone   text check (guardian_phone is null or guardian_phone ~ '^\+91[6-9][0-9]{9}$'),
  guardian_email   text,
  consent_at       timestamptz,
  consent_version  text,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index profiles_role_idx on public.profiles (role) where is_active;
create trigger profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

-- ---------- role helpers (SECURITY DEFINER so policies never recurse into profiles RLS) ----------

-- The caller's role, or NULL if not signed in, no profile, or deactivated.
-- Every policy goes through this, so deactivation takes effect on the very next request.
create function public.auth_role() returns public.user_role
language sql stable security definer set search_path = public as $$
  select p.role from public.profiles p where p.id = auth.uid() and p.is_active
$$;

create function public.role_rank(r public.user_role) returns int
language sql immutable as $$
  select case r when 'student' then 1 when 'mentor' then 2 when 'supervisor' then 3 when 'admin' then 4 end
$$;

-- True when the caller's role is at least the given role in the hierarchy.
create function public.has_role_at_least(r public.user_role) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.role_rank(public.auth_role()) >= public.role_rank(r), false)
$$;

-- ---------- mentor assignments (needed by can_view_student) ----------
create table public.mentor_assignments (
  id          uuid primary key default gen_random_uuid(),
  student_id  uuid not null references public.profiles (id) on delete cascade,
  mentor_id   uuid not null references public.profiles (id) on delete cascade,
  is_primary  boolean not null default false,
  assigned_by uuid references public.profiles (id),
  created_at  timestamptz not null default now(),
  unique (student_id, mentor_id),
  check (student_id <> mentor_id)
);
create unique index mentor_assignments_one_primary on public.mentor_assignments (student_id) where is_primary;
create index mentor_assignments_mentor_idx on public.mentor_assignments (mentor_id);

create function public.mentor_assignments_check() returns trigger
language plpgsql as $$
begin
  if not exists (select 1 from public.profiles where id = new.student_id and role = 'student') then
    raise exception 'student_id must belong to a student';
  end if;
  if not exists (select 1 from public.profiles where id = new.mentor_id and role = 'mentor' and is_active) then
    raise exception 'mentor_id must belong to an active mentor';
  end if;
  return new;
end;
$$;
create trigger mentor_assignments_check before insert or update on public.mentor_assignments
  for each row execute function public.mentor_assignments_check();

-- True when the caller may read data belonging to the given student:
--   student: only themselves; mentor: only assigned students; supervisor/admin: everyone.
create function public.can_view_student(sid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select case public.auth_role()
    when 'student'    then sid = auth.uid()
    when 'mentor'     then exists (
      select 1 from public.mentor_assignments ma
      where ma.student_id = sid and ma.mentor_id = auth.uid())
    when 'supervisor' then true
    when 'admin'      then true
    else false
  end
$$;

-- True when the caller is a mentor assigned to the given student.
create function public.is_assigned_mentor(sid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.auth_role() = 'mentor' and exists (
    select 1 from public.mentor_assignments ma
    where ma.student_id = sid and ma.mentor_id = auth.uid())
$$;

-- ---------- profile guards ----------

-- A signed-in user may edit only their own non-sensitive profile fields.
-- role, is_active, phone, email, date_of_birth and consent fields are changed only by admins
-- or by Edge Functions using the service role (auth.uid() is null there).
create function public.profiles_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  other_admins int;
begin
  -- Last-admin protection (applies to everyone, including the service role).
  if tg_op = 'DELETE' then
    if old.role = 'admin' and old.is_active then
      select count(*) into other_admins from public.profiles
        where role = 'admin' and is_active and id <> old.id;
      if other_admins = 0 then
        raise exception 'At least one active admin must always exist';
      end if;
    end if;
    return old;
  end if;

  if old.role = 'admin' and old.is_active and (new.role <> 'admin' or not new.is_active) then
    select count(*) into other_admins from public.profiles
      where role = 'admin' and is_active and id <> old.id;
    if other_admins = 0 then
      raise exception 'At least one active admin must always exist';
    end if;
  end if;

  -- Column protection for ordinary signed-in users.
  if auth.uid() is not null and public.auth_role() is distinct from 'admin' then
    if new.id <> old.id
       or new.role <> old.role
       or new.is_active <> old.is_active
       or new.email <> old.email
       or new.phone is distinct from old.phone
       or new.date_of_birth is distinct from old.date_of_birth
       or new.consent_at is distinct from old.consent_at
       or new.consent_version is distinct from old.consent_version then
      raise exception 'You cannot change role, status, email, phone, date of birth or consent details';
    end if;
  end if;
  return new;
end;
$$;
create trigger profiles_guard_update before update on public.profiles
  for each row execute function public.profiles_guard();
create trigger profiles_guard_delete before delete on public.profiles
  for each row execute function public.profiles_guard();

-- Creates the profile when an auth user is created.
-- The role is read ONLY from raw_app_meta_data, which can be set only with the service role.
-- Anything in raw_user_meta_data (which a visitor controls at sign-up) is never trusted for role.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  new_role public.user_role;
begin
  new_role := coalesce((new.raw_app_meta_data ->> 'role')::public.user_role, 'student');
  insert into public.profiles (id, role, full_name, email, phone)
  values (
    new.id,
    new_role,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(new.email, ''),
    public.normalize_phone(new.raw_user_meta_data ->> 'phone')
  );
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;

-- profiles SELECT: own row; a student sees their assigned mentors; a mentor sees assigned students;
-- supervisors and admins see everyone.
-- A deactivated user matches none of these (auth_role() is null), so they can read nothing.
create policy profiles_select on public.profiles for select to authenticated using (
  (id = auth.uid() and public.auth_role() is not null)
  or public.can_view_student(id)
  or exists (
    select 1 from public.mentor_assignments ma
    where ma.mentor_id = profiles.id and ma.student_id = auth.uid()
  )
  or public.has_role_at_least('supervisor')
);

-- profiles UPDATE: own row (sensitive columns blocked by trigger) or any row for admins.
create policy profiles_update on public.profiles for update to authenticated
  using (
    public.auth_role() is not null and (id = auth.uid() or public.auth_role() = 'admin')
  )
  with check (
    public.auth_role() is not null and (id = auth.uid() or public.auth_role() = 'admin')
  );
-- No INSERT or DELETE policies: profiles are created by the auth trigger and removed only
-- through the service role (data deletion requests), so both are denied to everyone else.

-- ---------- mentor_assignments RLS ----------
alter table public.mentor_assignments enable row level security;

-- SELECT: the student, the assigned mentor (all rows for their students), supervisors, admins.
create policy mentor_assignments_select on public.mentor_assignments for select to authenticated using (
  student_id = auth.uid()
  or mentor_id = auth.uid()
  or public.is_assigned_mentor(student_id)
  or public.has_role_at_least('supervisor')
);
-- INSERT/UPDATE/DELETE: supervisors and admins only (audited by the Edge Function that performs it).
create policy mentor_assignments_write on public.mentor_assignments for all to authenticated
  using (public.has_role_at_least('supervisor'))
  with check (public.has_role_at_least('supervisor'));

-- ---------- settings ----------
create table public.settings (
  key         text primary key,
  value       jsonb not null,
  description text not null default '',
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.profiles (id)
);
create trigger settings_updated_at before update on public.settings
  for each row execute function public.set_updated_at();

insert into public.settings (key, value, description) values
  ('program_name',          '"Foundation Maxxing"'::jsonb, 'Name shown in header, emails and tab title'),
  ('logo_url',              'null'::jsonb,                 'Logo image URL (supplied later)'),
  ('brand_colours',         '{"primary": null, "accent": null}'::jsonb, 'Brand colours (supplied later)'),
  ('fee_paise',             '200000'::jsonb,               'Monthly fee in paise'),
  ('capacity',              '10'::jsonb,                   'Maximum confirmed students'),
  ('registrations_open',    'true'::jsonb,                 'New registrations switch'),
  ('seat_hold_minutes',     '10'::jsonb,                   'Seat hold during payment, minutes'),
  ('cycle_days',            '30'::jsonb,                   'Days in a paid month'),
  ('refund_window_days',    '15'::jsonb,                   'Days after payment in which a refund is possible'),
  ('refund_percent',        '50'::jsonb,                   'Percent of cycle fee refunded inside the window'),
  ('renewal_reminder_days', '[5, 2]'::jsonb,               'Days before due date to send reminders'),
  ('grace_days',            '3'::jsonb,                    'Days after due date before lapse'),
  ('waitlist_offer_hours',  '24'::jsonb,                   'Waitlist offer validity, hours'),
  ('inactivity_days',       '7'::jsonb,                    'Days without study before a student is flagged inactive'),
  ('timer_safety_hours',    '6'::jsonb,                    'Running timers are auto-stopped after this many hours'),
  ('support_email',         '""'::jsonb,                   'Support contact email'),
  ('support_phone',         '""'::jsonb,                   'Support contact phone');

alter table public.settings enable row level security;

-- SELECT: any active signed-in user (settings hold no secrets).
create policy settings_select on public.settings for select to authenticated
  using (public.auth_role() is not null);
-- UPDATE: admins only. No INSERT or DELETE: the set of keys is fixed by migrations.
create policy settings_update on public.settings for update to authenticated
  using (public.auth_role() = 'admin')
  with check (public.auth_role() = 'admin');

-- Public (signed-out) landing page needs a few values. Exposes a fixed whitelist only.
create function public.public_settings() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
  from public.settings
  where key in ('program_name', 'logo_url', 'brand_colours', 'fee_paise', 'registrations_open',
                'refund_window_days', 'refund_percent', 'support_email', 'support_phone')
$$;
grant execute on function public.public_settings() to anon, authenticated;

-- ---------- community members ----------
create table public.community_members (
  id         uuid primary key default gen_random_uuid(),
  phone      text not null unique check (phone ~ '^\+91[6-9][0-9]{9}$'),
  name       text,
  added_by   uuid references public.profiles (id),
  created_at timestamptz not null default now()
);

alter table public.community_members enable row level security;

-- All operations: admins only. Registration checks run in an Edge Function with the service role,
-- so signed-out visitors and other roles can never read or enumerate this list.
create policy community_members_admin on public.community_members for all to authenticated
  using (public.auth_role() = 'admin')
  with check (public.auth_role() = 'admin');
