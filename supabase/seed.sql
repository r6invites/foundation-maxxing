-- =====================================================================
-- DEVELOPMENT / TEST SEED. NEVER RUN THIS IN PRODUCTION.
-- `supabase db reset` runs it automatically on a local stack. `supabase db push` does not.
-- Every account below is a labelled test account; all share the password  TestPass#2026
-- All syllabus rows are labelled SAMPLE and contain no real syllabus content.
-- =====================================================================

do $$
declare
  u record;
begin
  for u in
    select * from (values
      ('a0000000-0000-0000-0000-000000000001'::uuid, 'admin.test@fm-test.example',       'admin',      '[TEST] Admin',            null),
      ('a0000000-0000-0000-0000-000000000002'::uuid, 'supervisor.test@fm-test.example',  'supervisor', '[TEST] Supervisor',       null),
      ('a0000000-0000-0000-0000-000000000003'::uuid, 'mentor1.test@fm-test.example',     'mentor',     '[TEST] Mentor One',       null),
      ('a0000000-0000-0000-0000-000000000004'::uuid, 'mentor2.test@fm-test.example',     'mentor',     '[TEST] Mentor Two',       null),
      ('a0000000-0000-0000-0000-000000000005'::uuid, 'student1.test@fm-test.example',    'student',    '[TEST] Student One',      '9000000005'),
      ('a0000000-0000-0000-0000-000000000006'::uuid, 'student2.test@fm-test.example',    'student',    '[TEST] Student Two',      '9000000006')
    ) as t(id, email, role, full_name, phone)
  loop
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change
    ) values (
      '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email,
      extensions.crypt('TestPass#2026', extensions.gen_salt('bf')), now(),
      jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email'), 'role', u.role),
      jsonb_build_object('full_name', u.full_name, 'phone', u.phone),
      now(), now(), '', '', '', ''
    );
    insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
    values (
      gen_random_uuid(), u.id, u.id::text, 'email',
      jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
      now(), now(), now()
    );
  end loop;
end $$;

-- Student One has a confirmed seat and Mentor One; Student Two is enrolled but has NO mentor.
insert into public.enrollments (student_id, status, cycle_start, cycle_end, approved_by, approved_at) values
  ('a0000000-0000-0000-0000-000000000005', 'active', current_date, current_date + 30, 'a0000000-0000-0000-0000-000000000002', now()),
  ('a0000000-0000-0000-0000-000000000006', 'active', current_date, current_date + 30, 'a0000000-0000-0000-0000-000000000002', now());

insert into public.mentor_assignments (student_id, mentor_id, is_primary, assigned_by) values
  ('a0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000003', true, 'a0000000-0000-0000-0000-000000000002');

-- A few study entries so access rules can be seen working.
insert into public.study_sessions (student_id, source, started_at, ended_at, duration_seconds, note) values
  ('a0000000-0000-0000-0000-000000000005', 'manual', now() - interval '3 hours', now() - interval '2 hours', 3600, 'SAMPLE entry'),
  ('a0000000-0000-0000-0000-000000000006', 'manual', now() - interval '3 hours', now() - interval '1 hour', 7200, 'SAMPLE entry');

-- Community list: the two test student numbers.
insert into public.community_members (phone, name) values
  ('+919000000005', '[TEST] Student One'),
  ('+919000000006', '[TEST] Student Two');

-- SAMPLE syllabus (placeholder text only, not real syllabus content).
with paper as (
  insert into public.syllabus_nodes (level, code, title, sort_order, is_sample)
  values ('paper', 'SAMPLE-P1', 'SAMPLE Paper A', 1, true) returning id
), chapter as (
  insert into public.syllabus_nodes (parent_id, level, code, title, sort_order, is_sample)
  select id, 'chapter', 'SAMPLE-P1-C1', 'SAMPLE Chapter 1', 1, true from paper returning id
), sub as (
  insert into public.syllabus_nodes (parent_id, level, code, title, sort_order, is_sample)
  select id, 'sub_chapter', 'SAMPLE-P1-C1-S1', 'SAMPLE Sub-chapter 1', 1, true from chapter returning id
)
insert into public.syllabus_nodes (parent_id, level, code, title, sort_order, estimated_hours, is_sample)
select id, 'topic', 'SAMPLE-P1-C1-S1-T1', 'SAMPLE Topic 1', 1, 1.5, true from sub;
