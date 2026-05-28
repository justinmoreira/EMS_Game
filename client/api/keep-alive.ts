import { createClient } from '@supabase/supabase-js';

export default async function handler(request: Request): Promise<Response> {
  if (request.headers.get('authorization') !== `Bearer ${process.env.CRON_SECRET}`) {
    return Response.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const results = await Promise.all([
    ping('staging', process.env.SUPABASE_URL_STAGING, process.env.SUPABASE_SERVICE_KEY_STAGING),
    ping('prod', process.env.SUPABASE_URL_PROD, process.env.SUPABASE_SERVICE_KEY_PROD),
  ]);

  return Response.json({ results });
}

async function ping(env: string, url?: string, key?: string) {
  if (!url || !key) return { env, error: 'missing env vars' };

  const supabase = createClient(url, key);
  const { data: prev, error: selErr } = await supabase
    .from('keep_alive')
    .select('last_ping')
    .eq('id', 1)
    .single();
  if (selErr) return { env, error: selErr.message };

  const now = new Date().toISOString();
  const { error: updErr } = await supabase
    .from('keep_alive')
    .update({ last_ping: now })
    .eq('id', 1);

  return { env, was: prev.last_ping, now, error: updErr?.message ?? null };
}
