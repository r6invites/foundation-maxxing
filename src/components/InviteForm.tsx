import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { inviteUser } from '../lib/functions';
import { roleLabel } from '../lib/roles';
import { buttonClass, Field, inputClass } from './PublicShell';
import { ErrorMessage, SuccessMessage } from './Feedback';
import type { Role } from '../types';

const schema = z.object({
  full_name: z.string().trim().min(1, 'Enter a name').max(120),
  email: z.string().trim().min(1, 'Enter an email').email('Enter a valid email address'),
  role: z.enum(['student', 'mentor', 'supervisor', 'admin']),
  phone: z
    .string()
    .trim()
    .refine((v) => v === '' || /^(\+?91|0)?[\s-]?[6-9]\d{4}[\s-]?\d{5}$/.test(v), 'Enter a 10-digit Indian mobile number')
    .optional(),
});
type FormValues = z.infer<typeof schema>;

/** Invite someone by email. `roles` lists what the signed-in person is allowed to create. */
export function InviteForm({ roles }: { roles: Role[] }) {
  const [done, setDone] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const {
    register, handleSubmit, reset, formState: { errors, isSubmitting },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { role: roles[0] ?? 'mentor', phone: '' },
  });

  if (roles.length === 0) return null;

  const onSubmit = async (values: FormValues) => {
    setError(null);
    setDone(null);
    try {
      await inviteUser({
        email: values.email,
        full_name: values.full_name,
        role: values.role,
        ...(values.phone ? { phone: values.phone } : {}),
      });
      setDone(`Invitation sent to ${values.email}.`);
      reset({ role: values.role, phone: '', full_name: '', email: '' });
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not send the invitation. Please try again.');
    }
  };

  return (
    <form onSubmit={(e) => void handleSubmit(onSubmit)(e)} noValidate className="max-w-sm">
      <Field label="Full name" error={errors.full_name?.message}>
        <input className={inputClass} {...register('full_name')} />
      </Field>
      <Field label="Email" error={errors.email?.message}>
        <input type="email" className={inputClass} {...register('email')} />
      </Field>
      <Field label="Mobile number (optional)" error={errors.phone?.message}>
        <input type="tel" className={inputClass} {...register('phone')} />
      </Field>
      <Field label="Role" error={errors.role?.message}>
        <select className={inputClass} {...register('role')}>
          {roles.map((r) => (
            <option key={r} value={r}>
              {roleLabel(r)}
            </option>
          ))}
        </select>
      </Field>
      {error ? <ErrorMessage>{error}</ErrorMessage> : null}
      {done ? <SuccessMessage>{done}</SuccessMessage> : null}
      <button type="submit" disabled={isSubmitting} className={`${buttonClass} mt-3`}>
        {isSubmitting ? 'Sending…' : 'Send invitation'}
      </button>
    </form>
  );
}
