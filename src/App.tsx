import { HashRouter, Navigate, Route, Routes } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { AuthProvider, useAuth } from './auth/AuthProvider';
import { RequireRole } from './auth/RequireRole';
import { Layout } from './components/Layout';
import { Loading } from './components/Feedback';
import { useDocumentTitle } from './hooks/useBranding';
import { configError } from './lib/supabase';
import { homePathForRole } from './lib/roles';
import { Login } from './pages/Login';
import { ForgotPassword } from './pages/ForgotPassword';
import { AuthConfirm } from './pages/AuthConfirm';
import { SetPassword } from './pages/SetPassword';
import { StudentHome } from './pages/StudentHome';
import { MentorHome } from './pages/MentorHome';
import { SupervisorHome } from './pages/SupervisorHome';
import { AdminHome } from './pages/AdminHome';
import { NotFound } from './pages/NotFound';

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: 1, refetchOnWindowFocus: false } },
});

/** "/" sends people to their own home, or to the sign-in page. */
function RoleRedirect() {
  const { loading, profile } = useAuth();
  if (loading) return <Loading />;
  return <Navigate to={profile ? homePathForRole(profile.role) : '/login'} replace />;
}

function AppRoutes() {
  useDocumentTitle();
  return (
    <Routes>
      <Route path="/" element={<RoleRedirect />} />
      <Route path="/login" element={<Login />} />
      <Route path="/forgot-password" element={<ForgotPassword />} />
      <Route path="/auth/confirm" element={<AuthConfirm />} />
      <Route path="/set-password" element={<SetPassword />} />

      <Route element={<Layout />}>
        <Route element={<RequireRole roles={['student']} />}>
          <Route path="/student" element={<StudentHome />} />
        </Route>
        <Route element={<RequireRole roles={['mentor']} />}>
          <Route path="/mentor" element={<MentorHome />} />
        </Route>
        <Route element={<RequireRole roles={['supervisor']} />}>
          <Route path="/supervisor" element={<SupervisorHome />} />
        </Route>
        <Route element={<RequireRole roles={['admin']} />}>
          <Route path="/admin" element={<AdminHome />} />
        </Route>
      </Route>

      <Route path="*" element={<NotFound />} />
    </Routes>
  );
}

export default function App() {
  if (configError) {
    return (
      <p role="alert" className="m-4 rounded border border-red-300 bg-red-50 p-3 text-red-800">
        {configError}
      </p>
    );
  }
  return (
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <HashRouter>
          <AppRoutes />
        </HashRouter>
      </AuthProvider>
    </QueryClientProvider>
  );
}
