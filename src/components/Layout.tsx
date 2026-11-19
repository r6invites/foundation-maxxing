import { NavLink, Outlet } from 'react-router-dom';
import { useAuth } from '../auth/AuthProvider';
import { navItemsFor, roleLabel } from '../lib/roles';
import { useProgramName } from '../hooks/useBranding';

/** App shell for signed-in pages: header with program name, role-aware navigation, sign out. */
export function Layout() {
  const { profile, signOut } = useAuth();
  const programName = useProgramName();
  if (!profile) return null;

  return (
    <div className="min-h-screen">
      <header className="border-b p-3">
        <div className="mx-auto flex max-w-4xl flex-wrap items-center justify-between gap-3">
          <strong>{programName}</strong>
          <nav aria-label="Main" className="flex gap-3">
            {navItemsFor(profile.role).map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                className={({ isActive }) => (isActive ? 'font-semibold underline' : 'underline')}
              >
                {item.label}
              </NavLink>
            ))}
          </nav>
          <div className="flex items-center gap-3 text-sm">
            <span>
              {profile.full_name || profile.email} ({roleLabel(profile.role)})
            </span>
            <button type="button" onClick={() => void signOut()} className="rounded border px-2 py-1">
              Sign out
            </button>
          </div>
        </div>
      </header>
      <main className="mx-auto max-w-4xl p-4">
        <Outlet />
      </main>
    </div>
  );
}
