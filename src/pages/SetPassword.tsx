import { useState } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { supabase } from '../lib/supabase';
import { useAuth } from '../auth/AuthProvider';
import { MIN_PASSWORD_LENGTH } from '../config';
import { homePathForRole } from '../lib/roles';
import { buttonClass, Field, inputClass, PublicShell } from '../components/PublicShell';
import { ErrorMessage, Loading } from '../components/Feedback';

const schema = z
  .object({
    password: z.string().min(MIN_PASSWORD_LENGTH, `Use at least ${MIN_PASSWORD_LENGTH} characters`),
    confirm: z.string(),
  })
  .refine((v) => v.password === v.confirm, { path: ['confirm'], message: 'The two passwords do not match' });
type FormValues = z.infer<typeof schema>;

export function SetPassword() {
  const { loading, profile } = useAuth();
  const navigate = useNavigate();
  const [error, setError] = useState<string | null>(null);
  const {
    register, handleSubmit, formState: { errors, isSubmitting },
  } = useForm<FormValues>({ resolver: zodResolver(schema) });

  if (loading) return <Loading />;
  if (!profile) return <Navigate to="/login" replace />;

  const onSubmit = async (values: FormValues) => {
    setError(null);
    const { error: updateError } = await supabase.auth.updateUser({ password: values.password });
    if (updateError) {
      setError(
        /same|different/i.test(updateError.message)
          ? 'Please choose a password you have not used before.'
          : 'Could not save your password. Please try again.',
      );
      return;
    }
    navigate(homePathForRole(profile.role), { replace: true });
  };

  return (
    <PublicShell title="Choose a password">
      <form onSubmit={(e) => void handleSubmit(onSubmit)(e)} noValidate>
        <Field label="New password" error={errors.password?.message}>
          <input type="password" autoComplete="new-password" className={inputClass} {...register('password')} />
        </Field>
        <Field label="Repeat the password" error={errors.confirm?.message}>
          <input type="password" autoComplete="new-password" className={inputClass} {...register('confirm')} />
        </Field>
        {error ? <ErrorMessage>{error}</ErrorMessage> : null}
        <button type="submit" disabled={isSubmitting} className={`${buttonClass} mt-3`}>
          {isSubmitting ? 'Saving…' : 'Save password'}
        </button>
      </form>
    </PublicShell>
  );
}
