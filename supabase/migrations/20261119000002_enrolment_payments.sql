-- =====================================================================
-- 0002 enrolment, seats, payments, refunds, waitlist
-- Money is stored as integer paise. INR only.
-- Writes to these tables happen in Edge Functions (service role) after server-side checks;
-- RLS here only grants READ access, so the browser can never confirm a seat or a payment.
-- =====================================================================

-- ---------- enrollments (one row per student; status moves over time) ----------
create table public.enrollments (
  id               uuid primary key default gen_random_uuid(),
  student_id       uuid not null unique references public.profiles (id) on delete cascade,
  status           public.enrollment_status not null,
  cycle_start      date,
  cycle_end        date,
  leave_at         date,
  approved_by      uuid references public.profiles (id),
  approved_at      timestamptz,
  rejection_reason text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  check (cycle_end is null or cycle_start is null or cycle_end >= cycle_start),
  check (status <> 'rejected' or rejection_reason is not null)
);
create index enrollments_status_idx on public.enrollments (status);
create trigger enrollments_updated_at before update on public.enrollments
  for each row execute function public.set_updated_at();

alter table public.enrollments enable row level security;
-- SELECT: the student (own), assigned mentors, supervisors, admins. No write policies:
-- status changes are made only by Edge Functions / SQL functions with the service role.
create policy enrollments_select on public.enrollments for select to authenticated
  using (public.can_view_student(student_id));

-- ---------- seat holds ----------
create table public.seat_holds (
  id                uuid primary key default gen_random_uuid(),
  student_id        uuid not null references public.profiles (id) on delete cascade,
  status            public.hold_status not null default 'active',
  razorpay_order_id text unique,
  expires_at        timestamptz not null,
  created_at        timestamptz not null default now()
);
create unique index seat_holds_one_active_per_student on public.seat_holds (student_id) where status = 'active';
create index seat_holds_active_expiry_idx on public.seat_holds (expires_at) where status = 'active';

alter table public.seat_holds enable row level security;
-- SELECT: the student (own hold) and supervisors/admins. Writes: service role only.
create policy seat_holds_select on public.seat_holds for select to authenticated
  using (student_id = auth.uid() or public.has_role_at_least('supervisor'));

-- ---------- payments ----------
create table public.payments (
  id                   uuid primary key default gen_random_uuid(),
  student_id           uuid not null references public.profiles (id) on delete restrict,
  enrollment_id        uuid references public.enrollments (id) on delete set null,
  kind                 public.payment_kind not null default 'online',
  status               public.payment_status not null default 'created',
  amount_paise         integer not null check (amount_paise > 0),
  razorpay_order_id    text unique,
  razorpay_payment_id  text unique,
  cycle_start          date,
  cycle_end            date,
  note                 text,
  recorded_by          uuid references public.profiles (id),
  paid_at              timestamptz,
  created_at           timestamptz not null default now(),
  check (kind <> 'online' or razorpay_order_id is not null),
  check (kind <> 'manual' or (note is not null and btrim(note) <> '' and recorded_by is not null)),
  check (status <> 'paid' or paid_at is not null)
);
create index payments_student_idx on public.payments (student_id, created_at desc);

alter table public.payments enable row level security;
-- SELECT: the student (own), supervisors (monitoring: payment status), admins (ledger).
-- Mentors do not see payments. Writes: service role only.
create policy payments_select on public.payments for select to authenticated
  using (student_id = auth.uid() or public.has_role_at_least('supervisor'));

-- ---------- refunds ----------
create table public.refunds (
  id                  uuid primary key default gen_random_uuid(),
  payment_id          uuid not null references public.payments (id) on delete restrict,
  student_id          uuid not null references public.profiles (id) on delete restrict,
  kind                public.refund_kind not null,
  status              public.refund_status not null default 'requested',
  percent_applied     smallint not null check (percent_applied between 0 and 100),
  amount_paise        integer not null check (amount_paise >= 0),
  reason              text,
  decision_note       text,
  requested_at        timestamptz not null default now(),
  decided_by          uuid references public.profiles (id),
  decided_at          timestamptz,
  razorpay_refund_id  text unique,
  processed_at        timestamptz
);
create unique index refunds_one_open_per_payment on public.refunds (payment_id)
  where status in ('requested', 'approved');
create index refunds_status_idx on public.refunds (status);

alter table public.refunds enable row level security;
-- SELECT: the student (own), admins (refund desk), supervisors (read-only visibility).
-- Writes: Edge Functions only (request, approve, reject, process), each audited.
create policy refunds_select on public.refunds for select to authenticated
  using (student_id = auth.uid() or public.has_role_at_least('supervisor'));

-- ---------- waitlist ----------
create table public.waitlist (
  id                uuid primary key default gen_random_uuid(),
  full_name         text not null,
  phone             text not null check (phone ~ '^\+91[6-9][0-9]{9}$'),
  email             text not null,
  status            public.waitlist_status not null default 'waiting',
  position_seq      bigint generated always as identity,
  offered_at        timestamptz,
  offer_expires_at  timestamptz,
  offer_token_hash  text,
  created_at        timestamptz not null default now()
);
create unique index waitlist_one_open_per_phone on public.waitlist (phone)
  where status in ('waiting', 'offered');
create index waitlist_queue_idx on public.waitlist (position_seq) where status = 'waiting';

alter table public.waitlist enable row level security;
-- SELECT/UPDATE/DELETE: supervisors and admins (view and edit the waitlist).
-- INSERT: Edge Function only (after the community check). The offer token hash is never
-- exposed to the browser: the policy allows the row, and the client selects explicit columns.
create policy waitlist_staff on public.waitlist for all to authenticated
  using (public.has_role_at_least('supervisor'))
  with check (public.has_role_at_least('supervisor'));

-- ---------- seat counting (single source of truth) ----------

-- Confirmed seats = enrolments in awaiting_approval or active, plus unexpired active holds.
create function public.seats_taken() returns integer
language sql stable security definer set search_path = public as $$
  select (
    (select count(*) from public.enrollments where status in ('awaiting_approval', 'active'))
    + (select count(*) from public.seat_holds where status = 'active' and expires_at > now())
  )::int
$$;

create function public.seats_total() returns integer
language sql stable security definer set search_path = public as $$
  select (value #>> '{}')::int from public.settings where key = 'capacity'
$$;

-- Seats left is never negative even if an admin lowers capacity below current usage.
create function public.seats_left() returns integer
language sql stable security definer set search_path = public as $$
  select greatest(public.seats_total() - public.seats_taken(), 0)
$$;
grant execute on function public.seats_left() to anon, authenticated;

-- Atomically check capacity and create a hold. A transaction-level advisory lock serialises
-- every caller, so two people can never both take the last seat.
-- Returns the new hold id, or NULL when there is no seat (or registrations are closed).
create function public.create_seat_hold(p_student uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  hold_minutes int;
  open_flag    boolean;
  new_id       uuid;
begin
  perform pg_advisory_xact_lock(hashtext('foundation-maxxing:seats'));

  select (value #>> '{}')::boolean into open_flag from public.settings where key = 'registrations_open';
  if not coalesce(open_flag, false) then
    return null;
  end if;

  -- Free expired holds first so they never block a seat.
  update public.seat_holds set status = 'released' where status = 'active' and expires_at <= now();

  -- A student who already has an active hold keeps it.
  select id into new_id from public.seat_holds where student_id = p_student and status = 'active';
  if new_id is not null then
    return new_id;
  end if;

  if public.seats_taken() >= public.seats_total() then
    return null;
  end if;

  select (value #>> '{}')::int into hold_minutes from public.settings where key = 'seat_hold_minutes';
  insert into public.seat_holds (student_id, expires_at)
  values (p_student, now() + make_interval(mins => hold_minutes))
  returning id into new_id;
  return new_id;
end;
$$;

-- Used by the scheduled job: releases holds whose time has run out.
create function public.release_expired_holds() returns integer
language plpgsql security definer set search_path = public as $$
declare
  n integer;
begin
  update public.seat_holds set status = 'released' where status = 'active' and expires_at <= now();
  get diagnostics n = row_count;
  return n;
end;
$$;

-- Seat functions that change data are callable only by the service role (Edge Functions).
revoke all on function public.create_seat_hold(uuid) from public, anon, authenticated;
revoke all on function public.release_expired_holds() from public, anon, authenticated;
grant execute on function public.create_seat_hold(uuid) to service_role;
grant execute on function public.release_expired_holds() to service_role;
