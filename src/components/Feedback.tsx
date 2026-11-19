import type { ReactNode } from 'react';

export function Loading({ label = 'Loading…' }: { label?: string }) {
  return (
    <p role="status" className="p-4 text-sm text-gray-600">
      {label}
    </p>
  );
}

export function ErrorMessage({ children }: { children: ReactNode }) {
  return (
    <p role="alert" className="rounded border border-red-300 bg-red-50 p-3 text-sm text-red-800">
      {children}
    </p>
  );
}

export function EmptyState({ children }: { children: ReactNode }) {
  return <p className="p-3 text-sm text-gray-600">{children}</p>;
}

export function SuccessMessage({ children }: { children: ReactNode }) {
  return (
    <p role="status" className="rounded border border-green-300 bg-green-50 p-3 text-sm text-green-800">
      {children}
    </p>
  );
}
