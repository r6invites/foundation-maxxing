import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { requestPasswordReset } from '../lib/functions';
import { buttonClass, Field, inputClass, PublicShell } from '../components/PublicShell';
import { ErrorMessage, SuccessMessage } from '../components/Feedback';

const schema = z.object({
  email: z.string().trim().min(1, 'Enter your email').email('Enter a valid email address'),
});
type FormValues = z.infer<typeof schema>;

export function ForgotPassword() {
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const {
    register, handleSubmit, formState: { errors, isSubmitting },
  } = useForm<FormValues>({ resolver: zodResolver(schema) });

  const onSubmit = async (values: FormValues) => {
    setError(null);
    try {
      await requestPasswordReset(values.email);
      setSent(true);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Something went wrong. Please try again.');
    }
  };

  return (
    <PublicShell title="Reset your password">
      {sent ? (
        <SuccessMessage>
          If an account exists for that email, a reset link is on its way. It can take a few minutes to arrive.
        </SuccessMessage>
      ) : (
        <form onSubmit={(e) => void handleSubmit(onSubmit)(e)} noValidate>
          <Field label="Email" error={errors.email?.message}>
            <input type="email" autoComplete="email" className={inputClass} {...register('email')} />
          </Field>
          {error ? <ErrorMessage>{error}</ErrorMessage> : null}
          <button type="submit" disabled={isSubmitting} className={`${buttonClass} mt-3`}>
            {isSubmitting ? 'Sending…' : 'Send reset link'}
          </button>
        </form>
      )}
      <p className="mt-6 text-sm">
        <Link to="/login" className="underline">
          Back to sign in
        </Link>
      </p>
    </PublicShell>
  );
}
