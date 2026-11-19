import { useQuery } from '@tanstack/react-query';
import { supabase } from '../lib/supabase';
import { useAuth } from '../auth/AuthProvider';
import { invitableRoles } from '../lib/roles';
import { formatIST } from '../lib/time';
import { InviteForm } from '../components/InviteForm';
import { EmptyState, ErrorMessage, Loading } from '../components/Feedback';
import type { SettingRow } from '../types';

export function AdminHome() {
  const { profile } = useAuth();

  const settings = useQuery({
    queryKey: ['settings-list'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('settings').select('key, value, description, updated_at').order('key');
      if (error) throw error;
      return (data ?? []) as SettingRow[];
    },
  });

  return (
    <div>
      <h1 className="mb-4 text-xl font-semibold">Overview</h1>

      <h2 className="mb-2 font-semibold">Settings (read-only for now)</h2>
      {settings.isLoading ? <Loading /> : null}
      {settings.isError ? <ErrorMessage>Could not load the settings. Please refresh.</ErrorMessage> : null}
      {settings.data && settings.data.length === 0 ? <EmptyState>No settings found.</EmptyState> : null}
      {settings.data && settings.data.length > 0 ? (
        <div className="mb-8 overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead>
              <tr>
                <th className="p-1">Setting</th>
                <th className="p-1">Value</th>
                <th className="p-1">Last changed (IST)</th>
              </tr>
            </thead>
            <tbody>
              {settings.data.map((row) => (
                <tr key={row.key} className="border-t">
                  <td className="p-1">{row.key}</td>
                  <td className="p-1">{JSON.stringify(row.value)}</td>
                  <td className="p-1">{formatIST(row.updated_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}

      <h2 className="mb-3 font-semibold">Invite someone</h2>
      <InviteForm roles={profile ? invitableRoles(profile.role) : []} />
    </div>
  );
}
