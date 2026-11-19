// Creates an account by email invitation and sends the set-password link through sendEmail().
//
// Who may call it (enforced here, not in the browser):
//   admin       -> may invite any role
//   supervisor  -> may invite mentors only
// Everyone else, and deactivated users, are refused.
import { z } from 'zod';
import { fail, json, preflight } from '../_shared/http.ts';
import { adminClient, appLink, getCaller, getProgramName, writeAudit, type Role } from '../_shared/supabase.ts';
import { sendEmail } from '../_shared/email.ts';
import { inviteEmail } from '../_shared/templates.ts';

const bodySchema = z.object({
  email: z.string().trim().toLowerCase().email().max(254),
  full_name: z.string().trim().min(1).max(120),
  role: z.enum(['student', 'mentor', 'supervisor', 'admin']),
  phone: z.string().trim().max(20).refine(isIndianMobile).optional(),
});

/** 10-digit Indian mobile, optionally written with a 0, 91 or +91 prefix. The database normalises it. */
function isIndianMobile(value: string): boolean {
  const digits = value.replace(/\D/g, '');
  const local = digits.length === 12 && digits.startsWith('91') ? digits.slice(2)
    : digits.length === 11 && digits.startsWith('0') ? digits.slice(1)
    : digits;
  return /^[6-9]\d{9}$/.test(local);
}

Deno.serve(async (req) => {
  const early = preflight(req);
  if (early) return early;

  try {
    const admin = adminClient();
    const caller = await getCaller(req, admin);
    if (!caller) return fail(401, 'Please sign in again.');

    const parsed = bodySchema.safeParse(await req.json().catch(() => null));
    if (!parsed.success) return fail(400, 'Please check the name, email, mobile number and role, then try again.');
    const { email, full_name, role, phone } = parsed.data;

    const allowed: Role[] =
      caller.role === 'admin' ? ['student', 'mentor', 'supervisor', 'admin']
      : caller.role === 'supervisor' ? ['mentor']
      : [];
    if (!allowed.includes(role)) {
      return fail(403, 'You are not allowed to create this kind of account.');
    }

    // The role goes in app_metadata, which only the service role can set. The database trigger
    // reads the role from there and ignores user-editable metadata.
    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email,
      email_confirm: true,
      app_metadata: { role },
      user_metadata: { full_name, phone: phone ?? null },
    });
    if (createError || !created.user) {
      const duplicate = /already|registered|exists|database error/i.test(createError?.message ?? '');
      return fail(duplicate ? 409 : 500,
        duplicate ? 'An account with this email or phone number already exists.'
                  : 'Could not create the account. Please try again.');
    }
    const userId = created.user.id;

    // One-time link that signs the person in so they can choose a password.
    const { data: link, error: linkError } = await admin.auth.admin.generateLink({ type: 'recovery', email });
    const tokenHash = link?.properties?.hashed_token;
    if (linkError || !tokenHash) {
      await admin.auth.admin.deleteUser(userId);
      return fail(500, 'Could not prepare the invitation. Nothing was created; please try again.');
    }

    const programName = await getProgramName(admin);
    const message = inviteEmail({
      programName, fullName: full_name, role,
      link: appLink('/auth/confirm', { token_hash: tokenHash, type: 'recovery' }),
    });
    const sent = await sendEmail(admin, { to: email, template: 'invite', ...message });
    if (!sent) {
      // Keep the operation all-or-nothing so nobody is left with an account they cannot reach.
      await admin.auth.admin.deleteUser(userId);
      return fail(502, 'The invitation email could not be sent, so the account was not created. Please try again.');
    }

    await writeAudit(admin, {
      actor: caller.id, action: 'account.invite', entityType: 'profile', entityId: userId,
      details: { email, role },
    });

    return json({ ok: true, user_id: userId });
  } catch (e) {
    console.error('invite-user failed:', e);
    return fail(500, 'Something went wrong. Please try again.');
  }
});
