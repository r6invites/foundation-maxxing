import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

/** Set when the build was made without the two public Supabase values. The app shows it on screen. */
export const configError: string | null =
  url && anonKey
    ? null
    : 'This site is not connected to its database yet. VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY are missing.';

// Only the project URL and the public anon key ever reach the browser. Row Level Security
// decides what each signed-in user may read or change.
export const supabase = createClient(url ?? 'http://localhost:54321', anonKey ?? 'missing', {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    // The app uses HashRouter, so tokens in the URL would collide with routes. Email links carry a
    // token_hash that /auth/confirm exchanges explicitly instead.
    detectSessionInUrl: false,
  },
});
