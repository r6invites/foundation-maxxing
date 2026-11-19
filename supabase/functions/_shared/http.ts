// Small HTTP helpers shared by every Edge Function.

const allowedOrigin = (() => {
  const appUrl = Deno.env.get('APP_URL');
  if (!appUrl) return '*';
  try {
    return new URL(appUrl).origin;
  } catch {
    return '*';
  }
})();

export const corsHeaders = {
  'Access-Control-Allow-Origin': allowedOrigin,
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

/** A human-readable error the browser can show as-is. */
export function fail(status: number, message: string): Response {
  return json({ error: message }, status);
}

/** Handles CORS pre-flight and non-POST requests. Returns a Response to send, or null to continue. */
export function preflight(req: Request): Response | null {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return fail(405, 'Method not allowed');
  return null;
}
