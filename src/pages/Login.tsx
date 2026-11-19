import { useState } from 'react';
import { Link, Navigate } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { useAuth } from '../auth/AuthProvider';
import { homePathForRole } from '../lib/roles';
import { buttonClass, Field, inputClass, PublicShell } from '../components/PublicShell';
import { ErrorMessage, Loading } from '../components/Feedback';

const schema = z.object({
  email: z.string().trim().min(1, 'Enter your email').email('Enter a valid email address'),
  password: z.string().min(1, 'Enter your password'),
});
type FormValues = z.infer<typeof schema>;

export function Login() {
  const { loading, profile, notice, signIn } = useAuth();
  const [error, setError] = useState<string | null>(null);
  const {
    register, handleSubmit, formState: { errors, isSubmitting },
  } = useForm<FormValues>({ resolver: zodResolver(schema) });

  if (loading) return <Loading />;
  if (profile) return <Navigate to={homePathForRole(profile.role)} replace />;

  const onSubmit = async (values: FormValues) => {
    setError(null);
    try {
      await signIn(values.email, values.password);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not sign in. Please try again.');
    }
  };

  return (
    <PublicShell title="Sign in">
      {notice ? <ErrorMessage>{notice}</ErrorMessage> : null}
      <form onSubmit={(e) => void handleSubmit(onSubmit)(e)} noValidate className="mt-3">
        <Field label="Email" error={errors.email?.message}>
          <input type="email" autoComplete="username" className={inputClass} {...register('email')} />
        </Field>
        <Field label="Password" error={errors.password?.message}>
          <input type="password" autoComplete="current-password" className={inputClass} {...register('password')} />
        </Field>
        {error ? <ErrorMessage>{error}</ErrorMessage> : null}
        <div className="mt-3 flex items-center justify-between">
          <button type="submit" disabled={isSubmitting} className={buttonClass}>
            {isSubmitting ? 'Signing in…' : 'Sign in'}
          </button>
          <Link to="/forgot-password" className="text-sm underline">
            Forgot password?
          </Link>
        </div>
      </form>
    </PublicShell>
  );
}
