// Sends a password-reset link through sendEmail(). Callable while signed out.
// Always answers "ok" so it cannot be used to discover which emails have accounts.
import { z } from 'zod';
import { fail, json, preflight } from '../_shared/http.ts';
import { adminClient, appLink, getProgramName } from '../_shared/supabase.ts';
import { sendEmail } from '../_shared/email.ts';
import { passwordResetEmail } from '../_shared/templates.ts';

const bodySchema = z.object({ email: z.string().trim().toLowerCase().email().max(254) });

const MAX_REQUESTS_PER_HOUR = 5;

Deno.serve(async (req) => {
  const early = preflight(req);
  if (early) return early;

  try {
    const parsed = bodySchema.safeParse(await req.json().catch(() => null));
    if (!parsed.success) return fail(400, 'Please enter a valid email address.');
    const { email } = parsed.data;

    const admin = adminClient();

    // Rate limit per address: at most 5 reset emails an hour.
    const since = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const { count } = await admin
      .from('email_log')
      .select('id', { count: 'exact', head: true })
      .eq('to_email', email).eq('template', 'password_reset').gte('created_at', since);
    if ((count ?? 0) >= MAX_REQUESTS_PER_HOUR) return json({ ok: true });

    const { data: profile } = await admin
      .from('profiles').select('id, is_active').eq('email', email).maybeSingle();
    if (!profile || !profile.is_active) return json({ ok: true });

    const { data: link } = await admin.auth.admin.generateLink({ type: 'recovery', email });
    const tokenHash = link?.properties?.hashed_token;
    if (!tokenHash) return json({ ok: true });

    const programName = await getProgramName(admin);
    const message = passwordResetEmail({
      programName,
      link: appLink('/auth/confirm', { token_hash: tokenHash, type: 'recovery' }),
    });
    await sendEmail(admin, { to: email, template: 'password_reset', ...message });

    return json({ ok: true });
  } catch (e) {
    console.error('request-password-reset failed:', e);
    // Same answer as success: the visitor learns nothing from a failure.
    return json({ ok: true });
  }
});
