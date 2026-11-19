import { Navigate, Outlet } from 'react-router-dom';
import { useAuth } from './AuthProvider';
import { homePathForRole } from '../lib/roles';
import { Loading } from '../components/Feedback';
import type { Role } from '../types';

/**
 * Route guard. Signed-out visitors go to /login; signed-in users who open a page that is not for
 * their role are sent to their own home. This is a convenience: the database enforces access.
 */
export function RequireRole({ roles }: { roles: Role[] }) {
  const { loading, profile } = useAuth();
  if (loading) return <Loading label="Checking your sign-in…" />;
  if (!profile) return <Navigate to="/login" replace />;
  if (!roles.includes(profile.role)) return <Navigate to={homePathForRole(profile.role)} replace />;
  return <Outlet />;
}
