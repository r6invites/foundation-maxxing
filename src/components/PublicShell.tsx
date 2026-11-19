import type { ReactNode } from 'react';
import { useProgramName } from '../hooks/useBranding';

/** Plain centred card used by the sign-in and password screens. */
export function PublicShell({ title, children }: { title: string; children: ReactNode }) {
  const programName = useProgramName();
  return (
    <div className="mx-auto max-w-sm p-4">
      <p className="mb-6 text-lg font-semibold">{programName}</p>
      <h1 className="mb-4 text-xl font-semibold">{title}</h1>
      {children}
    </div>
  );
}

export function Field({
  label, error, children,
}: { label: string; error?: string | undefined; children: ReactNode }) {
  return (
    <label className="mb-3 block text-sm">
      <span className="mb-1 block">{label}</span>
      {children}
      {error ? (
        <span role="alert" className="mt-1 block text-red-700">
          {error}
        </span>
      ) : null}
    </label>
  );
}

export const inputClass = 'w-full rounded border p-2';
export const buttonClass = 'rounded border bg-gray-900 px-4 py-2 text-white disabled:opacity-50';
