import { useQuery } from '@tanstack/react-query';
import { supabase } from '../lib/supabase';
import { useAuth } from '../auth/AuthProvider';
import { EmptyState, ErrorMessage, Loading } from '../components/Feedback';
import { formatIST } from '../lib/time';
import type { EnrollmentStatus } from '../types';

const STATUS_TEXT: Record<EnrollmentStatus, string> = {
  awaiting_approval: 'Awaiting approval',
  active: 'Active',
  payment_due: 'Payment due',
  lapsed: 'Lapsed',
  refund_requested: 'Refund requested',
  left: 'Left the program',
  rejected: 'Not approved',
};

interface MentorRow {
  is_primary: boolean;
  mentor: { id: string; full_name: string } | null;
}

export function StudentHome() {
  const { profile } = useAuth();
  const userId = profile?.id ?? '';

  const enrollment = useQuery({
    queryKey: ['my-enrollment', userId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('enrollments').select('status, cycle_end').eq('student_id', userId).maybeSingle();
      if (error) throw error;
      return data as { status: EnrollmentStatus; cycle_end: string | null } | null;
    },
  });

  const mentors = useQuery({
    queryKey: ['my-mentors', userId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('mentor_assignments')
        .select('is_primary, mentor:profiles!mentor_assignments_mentor_id_fkey(id, full_name)')
        .eq('student_id', userId);
      if (error) throw error;
      return (data ?? []) as unknown as MentorRow[];
    },
  });

  return (
    <div>
      <h1 className="mb-4 text-xl font-semibold">Welcome, {profile?.full_name || 'student'}</h1>

      <section className="mb-6">
        <h2 className="mb-2 font-semibold">Status</h2>
        {enrollment.isLoading ? <Loading /> : null}
        {enrollment.isError ? <ErrorMessage>Could not load your status. Please refresh.</ErrorMessage> : null}
        {enrollment.data ? (
          <p>
            {STATUS_TEXT[enrollment.data.status]}
            {enrollment.data.cycle_end ? ` · current month ends ${formatIST(enrollment.data.cycle_end, 'dd MMM yyyy')}` : ''}
          </p>
        ) : null}
        {enrollment.isSuccess && !enrollment.data ? <EmptyState>You are not enrolled yet.</EmptyState> : null}
      </section>

      <section>
        <h2 className="mb-2 font-semibold">Your mentors</h2>
        {mentors.isLoading ? <Loading /> : null}
        {mentors.isError ? <ErrorMessage>Could not load your mentors. Please refresh.</ErrorMessage> : null}
        {mentors.data && mentors.data.length === 0 ? <EmptyState>No mentor has been assigned yet.</EmptyState> : null}
        <ul className="list-disc pl-5">
          {(mentors.data ?? []).map((row) => (
            <li key={row.mentor?.id}>
              {row.mentor?.full_name}
              {row.is_primary ? ' (primary)' : ''}
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}
