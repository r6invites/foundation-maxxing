import { useQuery } from '@tanstack/react-query';
import { supabase } from '../lib/supabase';
import { useAuth } from '../auth/AuthProvider';
import { EmptyState, ErrorMessage, Loading } from '../components/Feedback';

interface StudentRow {
  is_primary: boolean;
  student: { id: string; full_name: string } | null;
}

export function MentorHome() {
  const { profile } = useAuth();
  const userId = profile?.id ?? '';

  // The database only returns students assigned to this mentor; there is no filter to forget here.
  const students = useQuery({
    queryKey: ['my-students', userId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('mentor_assignments')
        .select('is_primary, student:profiles!mentor_assignments_student_id_fkey(id, full_name)')
        .eq('mentor_id', userId);
      if (error) throw error;
      return (data ?? []) as unknown as StudentRow[];
    },
  });

  return (
    <div>
      <h1 className="mb-4 text-xl font-semibold">My students</h1>
      {students.isLoading ? <Loading /> : null}
      {students.isError ? <ErrorMessage>Could not load your students. Please refresh.</ErrorMessage> : null}
      {students.data && students.data.length === 0 ? <EmptyState>No students are assigned to you yet.</EmptyState> : null}
      <ul className="list-disc pl-5">
        {(students.data ?? []).map((row) => (
          <li key={row.student?.id}>
            {row.student?.full_name}
            {row.is_primary ? ' (you are the primary mentor)' : ''}
          </li>
        ))}
      </ul>
    </div>
  );
}
