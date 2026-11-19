import type { SupabaseClient } from '@supabase/supabase-js';

export interface EmailMessage {
  to: string;
  subject: string;
  text: string;
  /** Short name of the email, stored in email_log (e.g. "invite", "password_reset"). */
  template: string;
}

/** The only thing the rest of the code knows about an email provider. */
interface EmailProvider {
  send(message: EmailMessage): Promise<{ id: string | null }>;
}

// Default provider: Resend. To switch provider, add another object with a send() method
// and return it from getProvider(). Nothing else in the code base changes.
const resendProvider: EmailProvider = {
  async send(message) {
    const key = Deno.env.get('RESEND_API_KEY');
    const from = Deno.env.get('EMAIL_FROM');
    if (!key || !from) throw new Error('Email is not configured (RESEND_API_KEY / EMAIL_FROM)');

    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from, to: [message.to], subject: message.subject, text: message.text }),
    });
    const body = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(`Email provider error ${response.status}: ${body?.message ?? 'unknown'}`);
    }
    return { id: typeof body?.id === 'string' ? body.id : null };
  },
};

function getProvider(): EmailProvider {
  return resendProvider;
}

/**
 * Sends one email and records the outcome in email_log.
 * Returns true when the provider accepted the message. Never throws for delivery problems.
 */
export async function sendEmail(admin: SupabaseClient, message: EmailMessage): Promise<boolean> {
  try {
    const { id } = await getProvider().send(message);
    await admin.from('email_log').insert({
      to_email: message.to, template: message.template, status: 'sent', provider_id: id,
    });
    return true;
  } catch (e) {
    const error = e instanceof Error ? e.message : String(e);
    await admin.from('email_log').insert({
      to_email: message.to, template: message.template, status: 'failed', error,
    });
    console.error(`sendEmail(${message.template}) failed:`, error);
    return false;
  }
}
