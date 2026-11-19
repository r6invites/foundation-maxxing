import { createClient, type SupabaseClient } from '@supabase/supabase-js';

export type Role = 'student' | 'mentor' | 'supervisor' | 'admin';

export interface Caller {
  id: string;
  role: Role;
  email: string;
}

/** Service-role client. Bypasses RLS: only use after the caller has been checked. */
export function adminClient(): SupabaseClient {
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) throw new Error('Supabase environment is not configured');
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

/**
 * Identifies the caller from the Authorization header and loads their role from the database.
 * Returns null when the token is missing or invalid, or the account is deactivated.
 * The role is always read from `profiles`, never from anything the browser sends.
 */
export async function getCaller(req: Request, admin: SupabaseClient): Promise<Caller | null> {
  const header = req.headers.get('Authorization') ?? '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (!token) return null;

  const { data: userData, error } = await admin.auth.getUser(token);
  if (error || !userData.user) return null;

  const { data: profile } = await admin
    .from('profiles')
    .select('id, role, email, is_active')
    .eq('id', userData.user.id)
    .maybeSingle();
  if (!profile || !profile.is_active) return null;

  return { id: profile.id as string, role: profile.role as Role, email: profile.email as string };
}

export async function writeAudit(
  admin: SupabaseClient,
  entry: {
    actor: string | null;
    action: string;
    entityType: string;
    entityId: string | null;
    details?: Record<string, unknown>;
    reason?: string | null;
  },
): Promise<void> {
  const { error } = await admin.rpc('write_audit', {
    p_action: entry.action,
    p_entity_type: entry.entityType,
    p_entity_id: entry.entityId,
    p_details: entry.details ?? {},
    p_reason: entry.reason ?? null,
    p_actor: entry.actor,
  });
  if (error) throw new Error(`Could not write audit log: ${error.message}`);
}

export async function getProgramName(admin: SupabaseClient): Promise<string> {
  const { data } = await admin.from('settings').select('value').eq('key', 'program_name').maybeSingle();
  return typeof data?.value === 'string' && data.value ? data.value : 'Foundation Maxxing';
}

/**
 * Builds a link into the single-page app. The app uses HashRouter, so the route lives after '#'.
 * APP_URL is the full site address, e.g. https://example.github.io/foundation-maxxing/
 */
export function appLink(path: string, params: Record<string, string>): string {
  const base = Deno.env.get('APP_URL');
  if (!base) throw new Error('APP_URL is not configured');
  const query = new URLSearchParams(params).toString();
  return `${base.replace(/\/+$/, '')}/#${path}?${query}`;
}
