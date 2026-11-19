-- =====================================================================
-- 0005 announcements, notifications, audit log, email log
-- =====================================================================

-- ---------- announcements ----------
create table public.announcements (
  id          uuid primary key default gen_random_uuid(),
  author_id   uuid not null references public.profiles (id),
  title       text not null check (btrim(title) <> ''),
  body        text not null,
  audience    public.announcement_audience not null,
  created_at  timestamptz not null default now()
);
create index announcements_created_idx on public.announcements (created_at desc);

alter table public.announcements enable row level security;
-- SELECT: students see 'students'/'both'; mentors see 'mentors'/'both'; supervisors and admins see all.
create policy announcements_select on public.announcements for select to authenticated using (
  public.has_role_at_least('supervisor')
  or (public.auth_role() = 'student' and audience in ('students', 'both'))
  or (public.auth_role() = 'mentor'  and audience in ('mentors', 'both'))
);
-- INSERT: supervisors and admins, as themselves. No UPDATE/DELETE.
create policy announcements_insert on public.announcements for insert to authenticated
  with check (author_id = auth.uid() and public.has_role_at_least('supervisor'));

-- ---------- notifications ----------
create table public.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  type        text not null,
  title       text not null,
  body        text,
  link        text,
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);
create index notifications_unread_idx on public.notifications (user_id) where read_at is null;

-- Users may only flip read_at on their own notifications.
create function public.notifications_guard() returns trigger
language plpgsql as $$
begin
  if auth.uid() is not null and (
       new.user_id <> old.user_id or new.type <> old.type or new.title <> old.title
       or new.body is distinct from old.body or new.link is distinct from old.link
       or new.created_at <> old.created_at) then
    raise exception 'Only the read state of a notification can be changed';
  end if;
  return new;
end;
$$;
create trigger notifications_guard before update on public.notifications
  for each row execute function public.notifications_guard();

alter table public.notifications enable row level security;
-- SELECT/UPDATE: only the owner (and only read_at, by trigger). INSERT/DELETE: service role only.
create policy notifications_select on public.notifications for select to authenticated
  using (user_id = auth.uid() and public.auth_role() is not null);
create policy notifications_update on public.notifications for update to authenticated
  using (user_id = auth.uid() and public.auth_role() is not null)
  with check (user_id = auth.uid());

-- ---------- audit log (append-only) ----------
create table public.audit_log (
  id           bigint generated always as identity primary key,
  actor_id     uuid references public.profiles (id) on delete set null,
  action       text not null,
  entity_type  text not null,
  entity_id    text,
  details      jsonb not null default '{}'::jsonb,
  reason       text,
  created_at   timestamptz not null default now()
);
create index audit_log_created_idx on public.audit_log (created_at desc);
create index audit_log_entity_idx on public.audit_log (entity_type, entity_id);

create function public.audit_log_immutable() returns trigger
language plpgsql as $$
begin
  raise exception 'The audit log is append-only';
end;
$$;
create trigger audit_log_no_update before update on public.audit_log
  for each row execute function public.audit_log_immutable();
create trigger audit_log_no_delete before delete on public.audit_log
  for each row execute function public.audit_log_immutable();

alter table public.audit_log enable row level security;
-- SELECT: supervisors and admins. INSERT: only via write_audit() (service role / triggers).
-- Nobody can update or delete rows.
create policy audit_log_select on public.audit_log for select to authenticated
  using (public.has_role_at_least('supervisor'));

create function public.write_audit(p_action text, p_entity_type text, p_entity_id text,
                                   p_details jsonb default '{}'::jsonb, p_reason text default null,
                                   p_actor uuid default null)
returns void
language sql security definer set search_path = public as $$
  insert into public.audit_log (actor_id, action, entity_type, entity_id, details, reason)
  values (coalesce(p_actor, auth.uid()), p_action, p_entity_type, p_entity_id, p_details, p_reason)
$$;
revoke all on function public.write_audit(text, text, text, jsonb, text, uuid) from public, anon, authenticated;
grant execute on function public.write_audit(text, text, text, jsonb, text, uuid) to service_role;

-- Settings changes are audited by the database itself, so no code path can skip it.
create function public.settings_audit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.updated_by := auth.uid();
  insert into public.audit_log (actor_id, action, entity_type, entity_id, details)
  values (auth.uid(), 'settings.update', 'setting', old.key,
          jsonb_build_object('from', old.value, 'to', new.value));
  return new;
end;
$$;
create trigger settings_audit before update on public.settings
  for each row when (old.value is distinct from new.value)
  execute function public.settings_audit();

-- ---------- email log ----------
create table public.email_log (
  id           uuid primary key default gen_random_uuid(),
  to_email     text not null,
  template     text not null,
  status       text not null check (status in ('sent', 'failed')),
  provider_id  text,
  error        text,
  created_at   timestamptz not null default now()
);
create index email_log_to_idx on public.email_log (to_email, created_at desc);

alter table public.email_log enable row level security;
-- SELECT: admins only. INSERT: service role only (from sendEmail()).
create policy email_log_select on public.email_log for select to authenticated
  using (public.auth_role() = 'admin');
