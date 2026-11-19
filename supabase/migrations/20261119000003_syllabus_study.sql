-- =====================================================================
-- 0003 syllabus, chapter progress, study sessions, screen-time reports
-- =====================================================================

-- ---------- syllabus ----------
create table public.syllabus_nodes (
  id               uuid primary key default gen_random_uuid(),
  parent_id        uuid references public.syllabus_nodes (id) on delete restrict,
  level            public.syllabus_level not null,
  code             text,
  title            text not null check (btrim(title) <> ''),
  sort_order       integer not null default 0,
  estimated_hours  numeric(6, 2) check (estimated_hours is null or estimated_hours >= 0),
  archived_at      timestamptz,
  is_sample        boolean not null default false,
  created_by       uuid references public.profiles (id),
  created_at       timestamptz not null default now(),
  check ((level = 'paper') = (parent_id is null))
);
create unique index syllabus_nodes_code_uniq on public.syllabus_nodes (code) where code is not null;
create index syllabus_nodes_parent_idx on public.syllabus_nodes (parent_id, sort_order);

alter table public.syllabus_nodes enable row level security;
-- SELECT: every active signed-in user (one master syllabus).
create policy syllabus_nodes_select on public.syllabus_nodes for select to authenticated
  using (public.auth_role() is not null);
-- INSERT/UPDATE: mentors, supervisors, admins. No DELETE: items are archived, never deleted.
create policy syllabus_nodes_insert on public.syllabus_nodes for insert to authenticated
  with check (public.has_role_at_least('mentor'));
create policy syllabus_nodes_update on public.syllabus_nodes for update to authenticated
  using (public.has_role_at_least('mentor'))
  with check (public.has_role_at_least('mentor'));

create table public.syllabus_uploads (
  id              uuid primary key default gen_random_uuid(),
  uploaded_by     uuid not null references public.profiles (id),
  filename        text not null,
  mode            text not null check (mode in ('replace', 'add')),
  added_count     integer not null default 0,
  changed_count   integer not null default 0,
  archived_count  integer not null default 0,
  created_at      timestamptz not null default now()
);
alter table public.syllabus_uploads enable row level security;
-- SELECT: mentors and above (upload history). INSERT: mentors and above, as themselves.
create policy syllabus_uploads_select on public.syllabus_uploads for select to authenticated
  using (public.has_role_at_least('mentor'));
create policy syllabus_uploads_insert on public.syllabus_uploads for insert to authenticated
  with check (public.has_role_at_least('mentor') and uploaded_by = auth.uid());

create table public.chapter_progress (
  student_id   uuid not null references public.profiles (id) on delete cascade,
  node_id      uuid not null references public.syllabus_nodes (id) on delete restrict,
  status       public.topic_status not null default 'pending',
  studied_at   timestamptz,
  verified_by  uuid references public.profiles (id),
  verified_at  timestamptz,
  updated_at   timestamptz not null default now(),
  primary key (student_id, node_id),
  check (status <> 'verified' or (verified_by is not null and verified_at is not null))
);
create trigger chapter_progress_updated_at before update on public.chapter_progress
  for each row execute function public.set_updated_at();

-- Students may only set Pending or Studied on their own rows; only mentors (assigned) and
-- admins may set Verified. Supervisors cannot verify (read-only on this table).
create function public.chapter_progress_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r public.user_role := public.auth_role();
begin
  if auth.uid() is null then
    return new;  -- service role
  end if;
  if new.status = 'verified' then
    if r not in ('mentor', 'admin') then
      raise exception 'Only a mentor or admin can verify a topic';
    end if;
    new.verified_by := auth.uid();
    new.verified_at := now();
  else
    if r <> 'student' then
      raise exception 'Only the student can mark a topic as studied or pending';
    end if;
    new.verified_by := null;
    new.verified_at := null;
    new.studied_at := case when new.status = 'studied' then coalesce(new.studied_at, now()) else null end;
  end if;
  return new;
end;
$$;
create trigger chapter_progress_guard before insert or update on public.chapter_progress
  for each row execute function public.chapter_progress_guard();

alter table public.chapter_progress enable row level security;
-- SELECT: the student, assigned mentors, supervisors, admins.
create policy chapter_progress_select on public.chapter_progress for select to authenticated
  using (public.can_view_student(student_id));
-- INSERT/UPDATE: the student on their own rows (Pending/Studied), assigned mentors and admins (Verified).
-- The guard trigger enforces which status each role may set. No DELETE.
create policy chapter_progress_insert on public.chapter_progress for insert to authenticated
  with check (
    student_id = auth.uid() and public.auth_role() = 'student'
    or public.is_assigned_mentor(student_id)
    or public.auth_role() = 'admin'
  );
create policy chapter_progress_update on public.chapter_progress for update to authenticated
  using (
    student_id = auth.uid() and public.auth_role() = 'student'
    or public.is_assigned_mentor(student_id)
    or public.auth_role() = 'admin'
  )
  with check (
    student_id = auth.uid() and public.auth_role() = 'student'
    or public.is_assigned_mentor(student_id)
    or public.auth_role() = 'admin'
  );

-- ---------- study sessions ----------
create table public.study_sessions (
  id                uuid primary key default gen_random_uuid(),
  student_id        uuid not null references public.profiles (id) on delete cascade,
  source            public.study_source not null,
  started_at        timestamptz not null,
  ended_at          timestamptz,
  -- Pause intervals: [{"start": "<iso>", "end": "<iso or null while paused>"}]
  pauses            jsonb not null default '[]'::jsonb check (jsonb_typeof(pauses) = 'array'),
  duration_seconds  integer check (duration_seconds is null or duration_seconds >= 0),
  node_id           uuid references public.syllabus_nodes (id),
  note              text,
  auto_stopped      boolean not null default false,
  locked_at         timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  check (ended_at is null or ended_at >= started_at),
  check (source <> 'manual' or (ended_at is not null and duration_seconds is not null)),
  check (ended_at is null or duration_seconds is not null)
);
-- Only one running (not yet stopped) timer per student, enforced by the database.
create unique index study_sessions_one_running on public.study_sessions (student_id) where ended_at is null;
create index study_sessions_student_time_idx on public.study_sessions (student_id, started_at desc);
create trigger study_sessions_updated_at before update on public.study_sessions
  for each row execute function public.set_updated_at();

alter table public.study_sessions enable row level security;
-- SELECT: the student, assigned mentors, supervisors, admins.
create policy study_sessions_select on public.study_sessions for select to authenticated
  using (public.can_view_student(student_id));
-- INSERT: the student, for themselves only (mentors, supervisors and admins cannot log study time).
create policy study_sessions_insert on public.study_sessions for insert to authenticated
  with check (student_id = auth.uid() and public.auth_role() = 'student');
-- UPDATE/DELETE: the student, for their own rows, only inside 24 hours of creation and unlocked.
-- Later changes by staff go through an audited Edge Function with the service role.
create policy study_sessions_update on public.study_sessions for update to authenticated
  using (student_id = auth.uid() and public.auth_role() = 'student'
         and locked_at is null and created_at > now() - interval '24 hours'
         or (student_id = auth.uid() and ended_at is null))
  with check (student_id = auth.uid() and public.auth_role() = 'student');
create policy study_sessions_delete on public.study_sessions for delete to authenticated
  using (student_id = auth.uid() and public.auth_role() = 'student'
         and locked_at is null and created_at > now() - interval '24 hours');

-- ---------- screen-time reports (self-reported) ----------
create table public.screen_time_reports (
  id               uuid primary key default gen_random_uuid(),
  student_id       uuid not null references public.profiles (id) on delete cascade,
  report_date      date not null,
  minutes          integer not null check (minutes between 0 and 1440),
  screenshot_path  text,
  note             text,
  locked_at        timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (student_id, report_date)
);
create trigger screen_time_reports_updated_at before update on public.screen_time_reports
  for each row execute function public.set_updated_at();

-- A report may be filed for any of the last 7 days (India time), never for the future.
create function public.screen_time_reports_check() returns trigger
language plpgsql as $$
declare
  today_ist date := (now() at time zone 'Asia/Kolkata')::date;
begin
  if tg_op = 'INSERT' and (new.report_date > today_ist or new.report_date < today_ist - 6) then
    raise exception 'A screen-time report can be added only for the last 7 days';
  end if;
  if tg_op = 'UPDATE' and new.report_date <> old.report_date then
    raise exception 'The report date cannot be changed';
  end if;
  return new;
end;
$$;
create trigger screen_time_reports_check before insert or update on public.screen_time_reports
  for each row execute function public.screen_time_reports_check();

alter table public.screen_time_reports enable row level security;
-- SELECT: the student, assigned mentors, supervisors, admins.
create policy screen_time_select on public.screen_time_reports for select to authenticated
  using (public.can_view_student(student_id));
-- INSERT: the student for themselves only.
create policy screen_time_insert on public.screen_time_reports for insert to authenticated
  with check (student_id = auth.uid() and public.auth_role() = 'student');
-- UPDATE/DELETE: the student, own rows, inside 24 hours of creation and unlocked.
create policy screen_time_update on public.screen_time_reports for update to authenticated
  using (student_id = auth.uid() and public.auth_role() = 'student'
         and locked_at is null and created_at > now() - interval '24 hours')
  with check (student_id = auth.uid());
create policy screen_time_delete on public.screen_time_reports for delete to authenticated
  using (student_id = auth.uid() and public.auth_role() = 'student'
         and locked_at is null and created_at > now() - interval '24 hours');

-- ---------- private storage bucket for screenshots ----------
-- Objects are stored at "<student_id>/<file>". The bucket is private, so only signed URLs work.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('screen-time', 'screen-time', false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = false, file_size_limit = 2097152,
      allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

-- READ: the owning student, their assigned mentors, supervisors and admins.
create policy screen_time_objects_select on storage.objects for select to authenticated
  using (
    bucket_id = 'screen-time'
    and public.can_view_student(((storage.foldername(name))[1])::uuid)
  );
-- WRITE: a student, only into their own folder. Type and size are also enforced by the bucket.
create policy screen_time_objects_insert on storage.objects for insert to authenticated
  with check (
    bucket_id = 'screen-time'
    and public.auth_role() = 'student'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy screen_time_objects_update on storage.objects for update to authenticated
  using (bucket_id = 'screen-time' and public.auth_role() = 'student'
         and (storage.foldername(name))[1] = auth.uid()::text);
create policy screen_time_objects_delete on storage.objects for delete to authenticated
  using (bucket_id = 'screen-time' and public.auth_role() = 'student'
         and (storage.foldername(name))[1] = auth.uid()::text);
