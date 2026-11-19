import { FunctionsHttpError } from '@supabase/supabase-js';
import { supabase } from './supabase';
import type { Role } from '../types';

/** Turns an Edge Function failure into a sentence a person can read. */
async function messageFrom(error: unknown): Promise<string> {
  if (error instanceof FunctionsHttpError) {
    try {
      const body = (await error.context.json()) as { error?: string };
      if (body.error) return body.error;
    } catch {
      // fall through to the generic message
    }
  }
  return 'Something went wrong. Please check your connection and try again.';
}

export async function requestPasswordReset(email: string): Promise<void> {
  const { error } = await supabase.functions.invoke('request-password-reset', { body: { email } });
  if (error) throw new Error(await messageFrom(error));
}

export interface InviteInput {
  email: string;
  full_name: string;
  role: Role;
  phone?: string;
}

export async function inviteUser(input: InviteInput): Promise<void> {
  const { error } = await supabase.functions.invoke('invite-user', { body: input });
  if (error) throw new Error(await messageFrom(error));
}
