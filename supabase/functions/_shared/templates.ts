// Email wording is fixed in code for Phase 1: plain, warm and short.

export function inviteEmail(opts: { programName: string; fullName: string; role: string; link: string }) {
  return {
    subject: `You're invited to ${opts.programName}`,
    text:
`Hi ${opts.fullName || 'there'},

You've been added to ${opts.programName} as a ${opts.role}.

Set your password and sign in here:
${opts.link}

This link works once and expires soon. If it has expired, ask the person who invited you to send a new one.

See you inside,
${opts.programName}`,
  };
}

export function passwordResetEmail(opts: { programName: string; link: string }) {
  return {
    subject: `Reset your ${opts.programName} password`,
    text:
`Hi,

We got a request to reset your ${opts.programName} password.

Choose a new password here:
${opts.link}

This link works once and expires soon. If you didn't ask for this, you can ignore this email and your password stays the same.

${opts.programName}`,
  };
}
