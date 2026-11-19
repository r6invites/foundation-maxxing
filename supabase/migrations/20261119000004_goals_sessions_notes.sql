-- =====================================================================
-- 0004 goals, mentoring sessions, session notes
-- =====================================================================

-- ---------- goals (one row per student; a goal for many students is many rows) ----------
create table public.goals (
  id            uuid primary key default gen_random_uuid(),
  student_id    uuid not null references public.profiles (id) on delete cascade,
  created_by    uuid not null references public.profiles (id),
  period        public.goal_period not null,
  period_start  date not null,
  title         text not null check (btrim(title) <> ''),
  description   text,
  node_ids      uuid[] not null default '{}',
  due_date      date,
  status        public.goal_status not null default 'pending',
  status_reason text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index goals_student_period_idx on public.goals (student_id, period_start desc);
create trigger goals_updated_at before update on public.goals
  for each row execute function public.set_updated_at();

create table public.goal_history (
  id                  uuid primary key default gen_random_uuid(),
  goal_id             uuid not null references public.goals (id) on delete cascade,
  changed_by          uuid references public.profiles (id),
  from_period_start   date,
  to_period_start     date,
  from_status         public.goal_status,
  to_status           public.goal_status,
  reason              text,
  created_at          timestamptz not null default now()
);

-- Students may only move their own goal between Pending and In progress, nothing else.
-- Every change to status or period is written to goal_history automatically.
create function public.goals_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and public.auth_role() = 'student' then
    if new.student_id <> old.student_id or new.title <> old.title
       or new.description is distinct from old.description
       or new.period <> old.period or new.period_start <> old.period_start
       or new.due_date is distinct from old.due_date or new.node_ids <> old.node_ids
       or new.created_by <> old.created_by then
      raise exception 'Students can only update the progress of their goals';
    end if;
    if new.status not in ('pending', 'in_progress') or old.status not in ('pending', 'in_progress') then
      raise exception 'Students can only set a goal to Pending or In progress';
    end if;
  end if;

  if new.status <> old.status or new.period_start <> old.period_start then
    insert into public.goal_history (goal_id, changed_by, from_period_start, to_period_start,
                                     from_status, to_status, reason)
    values (old.id, auth.uid(), old.period_start, new.period_start, old.status, new.status, new.status_reason);
  end if;
  return new;
end;
$$;
create trigger goals_guard before update on public.goals
  for each row execute function public.goals_guard();

alter table public.goals enable row level security;
-- SELECT: the student, assigned mentors, supervisors, admins.
create policy goals_select on public.goals for select to authenticated
  using (public.can_view_student(student_id));
-- INSERT: assigned mentors (as themselves) and admins.
create policy goals_insert on public.goals for insert to authenticated
  with check (
    created_by = auth.uid()
    and (public.is_assigned_mentor(student_id) or public.auth_role() = 'admin')
  );
-- UPDATE: assigned mentors and admins fully; the student only their own progress (guard trigger).
create policy goals_update on public.goals for update to authenticated
  using (
    public.is_assigned_mentor(student_id) or public.auth_role() = 'admin'
    or (student_id = auth.uid() and public.auth_role() = 'student')
  )
  with check (
    public.is_assigned_mentor(student_id) or public.auth_role() = 'admin'
    or (student_id = auth.uid() and public.auth_role() = 'student')
  );
-- No DELETE: goals are kept; unfinished ones are rescheduled or marked Missed.

alter table public.goal_history enable row level security;
-- SELECT: anyone who can read the goal. Rows are written only by the trigger above.
create policy goal_history_select on public.goal_history for select to authenticated
  using (exists (select 1 from public.goals g where g.id = goal_id and public.can_view_student(g.student_id)));

-- ---------- mentoring sessions ----------
create table public.mentoring_sessions (
  id                uuid primary key default gen_random_uuid(),
  created_by        uuid not null references public.profiles (id),
  title             text not null check (btrim(title) <> ''),
  starts_at         timestamptz not null,
  duration_minutes  integer not null check (duration_minutes between 5 and 600),
  mode              public.session_mode not null default 'online',
  meeting_link      text,
  location          text,
  agenda            text,
  status            public.session_status not null default 'scheduled',
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index mentoring_sessions_start_idx on public.mentoring_sessions (starts_at);
create index mentoring_sessions_creator_idx on public.mentoring_sessions (created_by, starts_at);
create trigger mentoring_sessions_updated_at before update on public.mentoring_sessions
  for each row execute function public.set_updated_at();

create table public.session_participants (
  session_id  uuid not null references public.mentoring_sessions (id) on delete cascade,
  student_id  uuid not null references public.profiles (id) on delete cascade,
  primary key (session_id, student_id)
);
create index session_participants_student_idx on public.session_participants (student_id);

create table public.session_reschedules (
  id                  uuid primary key default gen_random_uuid(),
  session_id          uuid not null references public.mentoring_sessions (id) on delete cascade,
  old_starts_at       timestamptz not null,
  old_duration_minutes integer not null,
  new_starts_at       timestamptz not null,
  new_duration_minutes integer not null,
  reason              text not null check (btrim(reason) <> ''),
  rescheduled_by      uuid not null references public.profiles (id),
  created_at          timestamptz not null default now()
);

-- True when the caller may see the session: a participant, an assigned mentor of any participant,
-- its creator, or a supervisor/admin.
create function public.can_view_session(sid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.has_role_at_least('supervisor')
    or exists (select 1 from public.mentoring_sessions s where s.id = sid and s.created_by = auth.uid())
    or exists (
      select 1 from public.session_participants sp
      where sp.session_id = sid and public.can_view_student(sp.student_id))
$$;

-- True when the caller may manage the session: its creator (a mentor) or an admin, and for a mentor
-- every participant must be one of their assigned students.
create function public.can_manage_session(sid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.auth_role() = 'admin'
    or (public.auth_role() = 'mentor'
        and exists (select 1 from public.mentoring_sessions s where s.id = sid and s.created_by = auth.uid()))
$$;

alter table public.mentoring_sessions enable row level security;
-- SELECT: participants, assigned mentors, creator, supervisors, admins.
create policy mentoring_sessions_select on public.mentoring_sessions for select to authenticated
  using (public.can_view_session(id));
-- INSERT: mentors and admins, as themselves.
create policy mentoring_sessions_insert on public.mentoring_sessions for insert to authenticated
  with check (created_by = auth.uid() and public.auth_role() in ('mentor', 'admin'));
-- UPDATE: the creating mentor or an admin. No DELETE: sessions are cancelled, not deleted.
create policy mentoring_sessions_update on public.mentoring_sessions for update to authenticated
  using (public.can_manage_session(id))
  with check (public.can_manage_session(id));

alter table public.session_participants enable row level security;
-- SELECT: whoever can see the session.
create policy session_participants_select on public.session_participants for select to authenticated
  using (public.can_view_session(session_id));
-- INSERT/DELETE: whoever manages the session, and (for mentors) only for their assigned students.
create policy session_participants_insert on public.session_participants for insert to authenticated
  with check (
    public.can_manage_session(session_id)
    and (public.auth_role() = 'admin' or public.is_assigned_mentor(student_id))
  );
create policy session_participants_delete on public.session_participants for delete to authenticated
  using (public.can_manage_session(session_id));

alter table public.session_reschedules enable row level security;
-- SELECT: whoever can see the session. INSERT: whoever manages it, as themselves. No UPDATE/DELETE (history).
create policy session_reschedules_select on public.session_reschedules for select to authenticated
  using (public.can_view_session(session_id));
create policy session_reschedules_insert on public.session_reschedules for insert to authenticated
  with check (rescheduled_by = auth.uid() and public.can_manage_session(session_id));

-- ---------- session notes ----------
create table public.session_notes (
  id           uuid primary key default gen_random_uuid(),
  session_id   uuid not null references public.mentoring_sessions (id) on delete restrict,
  author_id    uuid not null references public.profiles (id),
  visibility   public.note_visibility not null default 'private',
  covered      text,
  went_well    text,
  needs_work   text,
  action_items text,
  version      integer not null default 1,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index session_notes_session_idx on public.session_notes (session_id);
create trigger session_notes_updated_at before update on public.session_notes
  for each row execute function public.set_updated_at();

create table public.session_note_versions (
  id            uuid primary key default gen_random_uuid(),
  note_id       uuid not null references public.session_notes (id) on delete restrict,
  version       integer not null,
  visibility    public.note_visibility not null,
  covered       text,
  went_well     text,
  needs_work    text,
  action_items  text,
  edited_by     uuid references public.profiles (id),
  saved_at      timestamptz not null default now()
);

-- Edits keep the previous version automatically.
create function public.session_notes_version() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.session_note_versions (note_id, version, visibility, covered, went_well,
                                            needs_work, action_items, edited_by, saved_at)
  values (old.id, old.version, old.visibility, old.covered, old.went_well,
          old.needs_work, old.action_items, old.author_id, old.updated_at);
  new.version := old.version + 1;
  return new;
end;
$$;
create trigger session_notes_version before update on public.session_notes
  for each row execute function public.session_notes_version();

-- True when the caller may read the note:
--   private  -> author, supervisors, admins
--   mentors  -> additionally any mentor assigned to a participant of the session
--   student  -> additionally the participating students
create function public.can_read_note(nid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.session_notes n
    where n.id = nid and (
      n.author_id = auth.uid()
      or public.has_role_at_least('supervisor')
      or (n.visibility in ('mentors', 'student') and public.auth_role() = 'mentor' and exists (
            select 1 from public.session_participants sp
            where sp.session_id = n.session_id and public.is_assigned_mentor(sp.student_id)))
      or (n.visibility = 'student' and public.auth_role() = 'student' and exists (
            select 1 from public.session_participants sp
            where sp.session_id = n.session_id and sp.student_id = auth.uid()))
    )
  )
$$;

alter table public.session_notes enable row level security;
-- SELECT: per can_read_note above.
create policy session_notes_select on public.session_notes for select to authenticated
  using (public.can_read_note(id));
-- INSERT: a mentor (as author) on a session they can manage. Admins may write too.
create policy session_notes_insert on public.session_notes for insert to authenticated
  with check (author_id = auth.uid() and public.auth_role() in ('mentor', 'admin')
              and public.can_manage_session(session_id));
-- UPDATE: the author only (previous versions are kept by trigger). Supervisors and admins read only.
-- No DELETE policy: saved notes cannot be deleted.
create policy session_notes_update on public.session_notes for update to authenticated
  using (author_id = auth.uid() and public.auth_role() in ('mentor', 'admin'))
  with check (author_id = auth.uid());

alter table public.session_note_versions enable row level security;
-- SELECT: the author, supervisors and admins (history is never shown to students).
create policy session_note_versions_select on public.session_note_versions for select to authenticated
  using (exists (select 1 from public.session_notes n where n.id = note_id
                 and (n.author_id = auth.uid() or public.has_role_at_least('supervisor'))));
