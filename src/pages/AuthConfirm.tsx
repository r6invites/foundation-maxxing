import { useEffect, useRef, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import { PublicShell } from '../components/PublicShell';
import { ErrorMessage, Loading } from '../components/Feedback';

/**
 * Landing page for the links in invitation and password-reset emails:
 *   #/auth/confirm?token_hash=...&type=recovery
 * Exchanges the one-time token for a session, then asks the person to choose a password.
 */
export function AuthConfirm() {
  const [params] = useSearchParams();
  const navigate = useNavigate();
  const [error, setError] = useState<string | null>(null);
  const started = useRef(false); // the token works once; never exchange it twice

  useEffect(() => {
    if (started.current) return;
    started.current = true;

    const tokenHash = params.get('token_hash');
    if (!tokenHash || params.get('type') !== 'recovery') {
      setError('This link is not valid.');
      return;
    }
    void supabase.auth.verifyOtp({ token_hash: tokenHash, type: 'recovery' }).then(({ error: verifyError }) => {
      if (verifyError) {
        setError('This link has expired or was already used.');
      } else {
        navigate('/set-password', { replace: true });
      }
    });
  }, [params, navigate]);

  return (
    <PublicShell title="Checking your link">
      {error ? (
        <>
          <ErrorMessage>{error}</ErrorMessage>
          <p className="mt-4 text-sm">
            <Link to="/forgot-password" className="underline">
              Send me a new link
            </Link>
          </p>
        </>
      ) : (
        <Loading label="One moment…" />
      )}
    </PublicShell>
  );
}
