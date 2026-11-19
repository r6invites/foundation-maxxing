import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import type { Session } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';
import type { Profile } from '../types';

interface AuthState {
  /** True until we know whether someone is signed in and, if so, who they are. */
  loading: boolean;
  session: Session | null;
  profile: Profile | null;
  /** A message to show on the sign-in screen, for example after a deactivation. */
  notice: string | null;
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [sessionReady, setSessionReady] = useState(false);
  const [profileReady, setProfileReady] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);

  // 1. Track the Supabase session.
  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setSessionReady(true);
    });
    const { data } = supabase.auth.onAuthStateChange((_event, next) => {
      setSession(next);
      setSessionReady(true);
    });
    return () => data.subscription.unsubscribe();
  }, []);

  // 2. Load the profile whenever the signed-in user changes.
  const userId = session?.user.id ?? null;
  useEffect(() => {
    if (!sessionReady) return;
    if (!userId) {
      setProfile(null);
      setProfileReady(true);
      return;
    }
    let cancelled = false;
    setProfileReady(false);
    void supabase
      .from('profiles')
      .select('id, role, full_name, email, phone, is_active')
      .eq('id', userId)
      .maybeSingle()
      .then(({ data }) => {
        if (cancelled) return;
        const row = data as Profile | null;
        if (!row || !row.is_active) {
          // Row Level Security returns nothing for a deactivated account.
          setNotice('This account is not active. Please contact support.');
          setProfile(null);
          void supabase.auth.signOut();
        } else {
          setProfile(row);
        }
        setProfileReady(true);
      });
    return () => {
      cancelled = true;
    };
  }, [sessionReady, userId]);

  const signIn = useCallback(async (email: string, password: string) => {
    setNotice(null);
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim().toLowerCase(), password });
    if (error) {
      const tooMany = error.status === 429 || /rate limit|too many/i.test(error.message);
      throw new Error(
        tooMany
          ? 'Too many attempts. Please wait a few minutes and try again.'
          : 'That email and password do not match. Please try again.',
      );
    }
  }, []);

  const signOut = useCallback(async () => {
    await supabase.auth.signOut();
  }, []);

  const value = useMemo<AuthState>(
    () => ({
      loading: !sessionReady || !profileReady,
      session,
      profile,
      notice,
      signIn,
      signOut,
    }),
    [sessionReady, profileReady, session, profile, notice, signIn, signOut],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthState {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside AuthProvider');
  return ctx;
}
