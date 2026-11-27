-- pgTAP tests for access rules. Run with:  supabase test db
-- Uses the labelled accounts created by supabase/seed.sql.
-- Each test runs inside one transaction that is rolled back at the end.
begin;
select no_plan();

-- Seeded ids (see seed.sql)
--   admin 01, supervisor 02, mentor1 03, mentor2 04, student1 05 (assigned to mentor1), student2 06 (unassigned)

-- Helper: act as a signed-in user, the way PostgREST does it.
create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', uid::text, true);
  execute 'set local role authenticated';
end;
$$;
create function pg_temp.act_as_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role anon';
end;
$$;
create function pg_temp.reset_role() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
end;
$$;
create function pg_temp.affected(stmt text) returns integer language plpgsql as $$
declare n integer;
begin
  execute stmt;
  get diagnostics n = row_count;
  return n;
end;
$$;
grant execute on all functions in schema pg_temp to public;

-- ---------------------------------------------------------------------
-- 1. A mentor cannot read an unassigned student
-- ---------------------------------------------------------------------
select pg_temp.act_as('a0000000-0000-0000-0000-000000000003');  -- mentor1

select is((select count(*)::int from public.profiles where id = 'a0000000-0000-0000-0000-000000000005'), 1,
  'mentor1 can read assigned student1 profile');
select is((select count(*)::int from public.profiles where id = 'a0000000-0000-0000-0000-000000000006'), 0,
  'mentor1 cannot read unassigned student2 profile');
select is((select count(*)::int from public.study_sessions where student_id = 'a0000000-0000-0000-0000-000000000006'), 0,
  'mentor1 cannot read unassigned student2 study log');
select is((select count(*)::int from public.study_sessions where student_id = 'a0000000-0000-0000-0000-000000000005'), 1,
  'mentor1 can read assigned student1 study log');
select is((select count(*)::int from public.enrollments where student_id = 'a0000000-0000-0000-0000-000000000006'), 0,
  'mentor1 cannot read unassigned student2 enrolment');
select is((select count(*)::int from public.payments), 0, 'mentors cannot read payments');
select is((select count(*)::int from public.community_members), 0, 'mentors cannot read the community list');

select pg_temp.reset_role();
select pg_temp.act_as('a0000000-0000-0000-0000-000000000004');  -- mentor2, no students
select is((select count(*)::int from public.profiles where role = 'student'), 0,
  'mentor2 with no assignments sees no students at all');

-- ---------------------------------------------------------------------
-- 2. A student cannot read another student
-- ---------------------------------------------------------------------
select pg_temp.reset_role();
select pg_temp.act_as('a0000000-0000-0000-0000-000000000005');  -- student1

select is((select count(*)::int from public.profiles where id = 'a0000000-0000-0000-0000-000000000006'), 0,
  'student1 cannot read student2 profile');
select is((select count(*)::int from public.study_sessions where student_id = 'a0000000-0000-0000-0000-000000000006'), 0,
  'student1 cannot read student2 study log');
select is((select count(*)::int from public.enrollments where student_id = 'a0000000-0000-0000-0000-000000000006'), 0,
  'student1 cannot read student2 enrolment');
select is((select count(*)::int from public.profiles where id = 'a0000000-0000-0000-0000-000000000005'), 1,
  'student1 can read their own profile');
select is((select count(*)::int from public.profiles where id = 'a0000000-0000-0000-0000-000000000003'), 1,
  'student1 can read their assigned mentor');
select is((select count(*)::int from public.profiles where id = 'a0000000-0000-0000-0000-000000000004'), 0,
  'student1 cannot read a mentor who is not assigned');

-- ---------------------------------------------------------------------
-- 3. Settings: only admins may change them
-- ---------------------------------------------------------------------
select pg_temp.reset_role();
select pg_temp.act_as('a0000000-0000-0000-0000-000000000002');  -- supervisor
select is(
  pg_temp.affected($$update public.settings set value = '99'::jsonb where key = 'capacity'$$),
  0, 'supervisor cannot change settings');
select is((select count(*)::int from public.settings where key = 'capacity'), 1, 'supervisor can read settings');

select pg_temp.reset_role();
select pg_temp.act_as('a0000000-0000-0000-0000-000000000003');  -- mentor
select is(
  pg_temp.affected($$update public.settings set value = '99'::jsonb where key = 'capacity'$$),
  0, 'mentor cannot change settings');

select pg_temp.reset_role();
select pg_temp.act_as('a0000000-0000-0000-0000-000000000005');  -- student
select is(
  pg_temp.affected($$update public.settings set value = '99'::jsonb where key = 'capacity'$$),
  0, 'student cannot change settings');

select pg_temp.reset_role();
select pg_temp.act_as('a0000000-0000-0000-0000-000000000001');  -- admin
select is(
  pg_temp.affected($$update public.settings set value = '12'::jsonb where key = 'capacity'$$),
  1, 'admin can change settings');
select is((select value from public.settings where key = 'capacity'), '12'::jsonb, 'admin change is stored');
select is((select count(*)::int from public.audit_log where action = 'settings.update' and entity_id = 'capacity'), 1,
  'settings change wrote an audit row');

-- ---------------------------------------------------------------------
-- 4. Hierarchy: supervisors and admins see everyone, community list is admin only
-- ---------------------------------------------------------------------
select is((select count(*)::int from public.community_members), 2, 'admin can read the community list');
select pg_temp.reset_role();
select pg_temp.act_as('a0000000-0000-0000-0000-000000000002');
select is((select count(*)::int from public.profiles), 6, 'supervisor sees all profiles');
select is((select count(*)::int from public.community_members), 0, 'supervisor cannot read the community list');
select is((select count(*)::int from public.audit_log), 1, 'supervisor can read the audit log');

-- ---------------------------------------------------------------------
-- 5. Signed-out visitors see nothing, except the public settings function
-- ---------------------------------------------------------------------
select pg_temp.reset_role();
select pg_temp.act_as_anon();
select throws_ok($$select count(*) from public.profiles$$, '42501', null, 'anon has no access to profiles');
select throws_ok($$select count(*) from public.settings$$, '42501', null, 'anon has no direct access to settings');
select throws_ok($$select count(*) from public.community_members$$, '42501', null, 'anon has no access to the community list');
select ok((public.public_settings() ->> 'program_name') is not null, 'anon can read public settings');
select ok(not (public.public_settings() ? 'capacity'), 'public settings do not expose capacity');

-- ---------------------------------------------------------------------
-- 6. Users cannot escalate or tamper with their own profile
-- ---------------------------------------------------------------------
select pg_temp.reset_role();
select pg_temp.act_as('a0000000-0000-0000-0000-000000000005');
select throws_ok(
  $$update public.profiles set role = 'admin' where id = 'a0000000-0000-0000-0000-000000000005'$$,
  'P0001', null, 'student cannot make themselves admin');
select throws_ok(
  $$update public.profiles set phone = '+919111111111' where id = 'a0000000-0000-0000-0000-000000000005'$$,
  'P0001', null, 'student cannot change their own phone');
select lives_ok(
  $$update public.profiles set city = 'Chennai' where id = 'a0000000-0000-0000-0000-000000000005'$$,
  'student can change their own city');
select is(
  pg_temp.affected($$update public.profiles set city = 'X' where id = 'a0000000-0000-0000-0000-000000000006'$$),
  0, 'student cannot edit another student');

-- ---------------------------------------------------------------------
-- 7. Money and seats are not writable from the browser
-- ---------------------------------------------------------------------
select throws_ok(
  $$insert into public.payments (student_id, kind, status, amount_paise, razorpay_order_id, paid_at)
    values ('a0000000-0000-0000-0000-000000000005', 'online', 'paid', 200000, 'order_x', now())$$,
  '42501', null, 'student cannot insert a payment');
select throws_ok(
  $$insert into public.seat_holds (student_id, expires_at)
    values ('a0000000-0000-0000-0000-000000000005', now() + interval '1 hour')$$,
  '42501', null, 'student cannot create a seat hold directly');
select is(
  pg_temp.affected($$update public.enrollments set status = 'active' where student_id = 'a0000000-0000-0000-0000-000000000005'$$),
  0, 'student cannot change their enrolment status');
select throws_ok($$select public.create_seat_hold('a0000000-0000-0000-0000-000000000005')$$, '42501', null,
  'student cannot call create_seat_hold');

-- ---------------------------------------------------------------------
-- 8. Audit log is append-only and not readable by students
-- ---------------------------------------------------------------------
select is((select count(*)::int from public.audit_log), 0, 'student cannot read the audit log');
select pg_temp.reset_role();
select throws_ok($$update public.audit_log set action = 'x'$$, 'P0001', 'The audit log is append-only',
  'audit log rows cannot be updated, even by the database owner');
select throws_ok($$delete from public.audit_log$$, 'P0001', 'The audit log is append-only',
  'audit log rows cannot be deleted');

-- ---------------------------------------------------------------------
-- 9. Goals: mentors only for assigned students; students only change progress
-- ---------------------------------------------------------------------
select pg_temp.act_as('a0000000-0000-0000-0000-000000000003');  -- mentor1
select lives_ok(
  $$insert into public.goals (student_id, created_by, period, period_start, title)
    values ('a0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000003', 'weekly', current_date, 'G1')$$,
  'mentor1 can set a goal for assigned student1');
select throws_ok(
  $$insert into public.goals (student_id, created_by, period, period_start, title)
    values ('a0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000003', 'weekly', current_date, 'G2')$$,
  '42501', null, 'mentor1 cannot set a goal for unassigned student2');

select pg_temp.reset_role();
select pg_temp.act_as('a0000000-0000-0000-0000-000000000005');  -- student1
select lives_ok($$update public.goals set status = 'in_progress' where title = 'G1'$$,
  'student can set their goal to In progress');
select throws_ok($$update public.goals set status = 'done' where title = 'G1'$$, 'P0001', null,
  'student cannot mark their own goal Done');
select throws_ok($$update public.goals set title = 'changed' where title = 'G1'$$, 'P0001', null,
  'student cannot rewrite a goal');

-- ---------------------------------------------------------------------
-- 10. Session note visibility
-- ---------------------------------------------------------------------
select pg_temp.reset_role();
insert into public.mentor_assignments (student_id, mentor_id)
  values ('a0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000004');  -- mentor2 now co-mentor
insert into public.mentoring_sessions (id, created_by, title, starts_at, duration_minutes)
  values ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000003', 'S1', now() + interval '1 day', 60);
insert into public.session_participants values
  ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000005');
insert into public.session_notes (id, session_id, author_id, visibility, covered) values
  ('c0000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000003', 'private', 'p'),
  ('c0000000-0000-0000-0000-000000000002', 'b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000003', 'mentors', 'm'),
  ('c0000000-0000-0000-0000-000000000003', 'b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000003', 'student', 's');

select pg_temp.act_as('a0000000-0000-0000-0000-000000000005');  -- student1
select is((select string_agg(covered, ',' order by covered) from public.session_notes), 's',
  'student sees only notes shared with the student');
select pg_temp.reset_role();
select pg_temp.act_as('a0000000-0000-0000-0000-000000000004');  -- mentor2 (co-mentor, not author)
select is((select string_agg(covered, ',' order by covered) from public.session_notes), 'm,s',
  'co-mentor sees mentor-shared and student-shared notes, not private ones');
select pg_temp.reset_role();
select pg_temp.act_as('a0000000-0000-0000-0000-000000000003');  -- author
select is((select count(*)::int from public.session_notes), 3, 'author sees all own notes');
select is(pg_temp.affected($$delete from public.session_notes$$), 0,
  'a mentor cannot delete a saved note');
select lives_ok($$update public.session_notes set covered = 'p2' where id = 'c0000000-0000-0000-0000-000000000001'$$,
  'author can edit a note');
select is((select count(*)::int from public.session_note_versions where note_id = 'c0000000-0000-0000-0000-000000000001'), 1,
  'edit kept the previous version');
select pg_temp.reset_role();
select pg_temp.act_as('a0000000-0000-0000-0000-000000000002');  -- supervisor
select is((select count(*)::int from public.session_notes), 3, 'supervisor reads all notes');
select is(pg_temp.affected($$update public.session_notes set covered = 'z'$$), 0,
  'supervisor cannot edit notes');

-- ---------------------------------------------------------------------
-- 11. Chapter progress: Studied by student, Verified by assigned mentor or admin
-- ---------------------------------------------------------------------
select pg_temp.reset_role();
select pg_temp.act_as('a0000000-0000-0000-0000-000000000005');  -- student1
select lives_ok(
  $$insert into public.chapter_progress (student_id, node_id, status)
    select 'a0000000-0000-0000-0000-000000000005', id, 'studied' from public.syllabus_nodes where level = 'topic'$$,
  'student can mark a topic Studied');
select throws_ok(
  $$update public.chapter_progress set status = 'verified' where student_id = 'a0000000-0000-0000-0000-000000000005'$$,
  'P0001', null, 'student cannot verify their own topic');
select pg_temp.reset_role();
select pg_temp.act_as('a0000000-0000-0000-0000-000000000003');  -- mentor1 (assigned)
select lives_ok(
  $$update public.chapter_progress set status = 'verified' where student_id = 'a0000000-0000-0000-0000-000000000005'$$,
  'assigned mentor can verify');
select pg_temp.reset_role();
select pg_temp.act_as('a0000000-0000-0000-0000-000000000002');  -- supervisor
select is(
  pg_temp.affected($$update public.chapter_progress set status = 'pending'$$), 0,
  'supervisor cannot change chapter progress');

-- ---------------------------------------------------------------------
-- 12. Seat counter never exceeds capacity
-- ---------------------------------------------------------------------
select pg_temp.reset_role();
update public.settings set value = '3'::jsonb where key = 'capacity';   -- two active students already count
select isnt(public.create_seat_hold('a0000000-0000-0000-0000-000000000001'), null, 'first free seat is held');
select is(public.seats_taken(), 3, 'seat counter includes the hold');
select is(public.create_seat_hold('a0000000-0000-0000-0000-000000000002'), null, 'no hold when the program is full');
select is(public.seats_left(), 0, 'seats left is zero');
update public.settings set value = '1'::jsonb where key = 'capacity';  -- lowered below usage
select is(public.seats_left(), 0, 'seats left never goes negative after capacity is lowered');
update public.seat_holds set expires_at = now() - interval '1 minute';
select is(public.release_expired_holds(), 1, 'expired hold is released');
update public.settings set value = '10'::jsonb where key = 'capacity';
update public.settings set value = 'false'::jsonb where key = 'registrations_open';
select is(public.create_seat_hold('a0000000-0000-0000-0000-000000000002'), null, 'no hold when registrations are closed');

-- ---------------------------------------------------------------------
-- 13. Last admin, deactivation and role assignment at sign-up
-- ---------------------------------------------------------------------
select throws_ok(
  $$update public.profiles set is_active = false where id = 'a0000000-0000-0000-0000-000000000001'$$,
  'P0001', 'At least one active admin must always exist', 'the last active admin cannot be deactivated');
select throws_ok(
  $$update public.profiles set role = 'mentor' where id = 'a0000000-0000-0000-0000-000000000001'$$,
  'P0001', 'At least one active admin must always exist', 'the last admin cannot be demoted');

update public.profiles set is_active = false where id = 'a0000000-0000-0000-0000-000000000003';
select pg_temp.act_as('a0000000-0000-0000-0000-000000000003');
select is((select count(*)::int from public.profiles), 0, 'a deactivated mentor can read nothing');
select is((select count(*)::int from public.study_sessions), 0, 'a deactivated mentor cannot read study logs');
select pg_temp.reset_role();

insert into auth.users (instance_id, id, aud, role, email, raw_app_meta_data, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'sneaky@fm-test.example', '{}', '{"role":"admin","full_name":"Sneaky"}'),
  ('00000000-0000-0000-0000-000000000000', 'd0000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'invited@fm-test.example', '{"role":"supervisor"}', '{"full_name":"Invited"}');
select is((select role::text from public.profiles where id = 'd0000000-0000-0000-0000-000000000001'), 'student',
  'a role in user-controlled sign-up metadata is ignored');
select is((select role::text from public.profiles where id = 'd0000000-0000-0000-0000-000000000002'), 'supervisor',
  'a role in server-controlled app metadata is honoured');

-- ---------------------------------------------------------------------
-- 14. Phone normalisation
-- ---------------------------------------------------------------------
select is(public.normalize_phone('98765 43210'), '+919876543210', 'spaces are stripped');
select is(public.normalize_phone('098765-43210'), '+919876543210', 'leading 0 and dashes are stripped');
select is(public.normalize_phone('+91 98765 43210'), '+919876543210', '+91 prefix is stripped and re-added');
select is(public.normalize_phone('919876543210'), '+919876543210', '91 prefix is handled');
select throws_ok($$select public.normalize_phone('12345')$$, '22023', null, 'short numbers are rejected');
select is(public.normalize_phone('  '), null, 'blank is null');

select * from finish();
rollback;
