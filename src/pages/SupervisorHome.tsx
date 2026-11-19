import { useQuery } from '@tanstack/react-query';
import { supabase } from '../lib/supabase';
import { useAuth } from '../auth/AuthProvider';
import { invitableRoles } from '../lib/roles';
import { InviteForm } from '../components/InviteForm';
import { ErrorMessage, Loading } from '../components/Feedback';

export function SupervisorHome() {
  const { profile } = useAuth();

  const numbers = useQuery({
    queryKey: ['supervisor-numbers'],
    queryFn: async () => {
      const [students, mentors, awaiting] = await Promise.all([
        supabase.from('profiles').select('id', { count: 'exact', head: true }).eq('role', 'student'),
        supabase.from('profiles').select('id', { count: 'exact', head: true }).eq('role', 'mentor'),
        supabase.from('enrollments').select('id', { count: 'exact', head: true }).eq('status', 'awaiting_approval'),
      ]);
      const failed = [students, mentors, awaiting].find((r) => r.error);
      if (failed?.error) throw failed.error;
      return {
        students: students.count ?? 0,
        mentors: mentors.count ?? 0,
        awaiting: awaiting.count ?? 0,
      };
    },
  });

  return (
    <div>
      <h1 className="mb-4 text-xl font-semibold">Overview</h1>
      {numbers.isLoading ? <Loading /> : null}
      {numbers.isError ? <ErrorMessage>Could not load the numbers. Please refresh.</ErrorMessage> : null}
      {numbers.data ? (
        <ul className="mb-8 list-disc pl-5">
          <li>Students: {numbers.data.students}</li>
          <li>Mentors: {numbers.data.mentors}</li>
          <li>Registrations awaiting approval: {numbers.data.awaiting}</li>
        </ul>
      ) : null}

      <h2 className="mb-3 font-semibold">Invite a mentor</h2>
      <InviteForm roles={profile ? invitableRoles(profile.role) : []} />
    </div>
  );
}
