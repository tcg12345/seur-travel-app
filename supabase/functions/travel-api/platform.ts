import { Problem, requireValue } from './validation.ts';
export const projectURL = Deno.env.get('SUPABASE_URL')!;
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
export const apiURL = projectURL + '/functions/v1/travel-api';
export async function platform(
  path: string,
  method = 'GET',
  body?: unknown,
  extra: Record<string, string> = {},
) {
  const r = await fetch(projectURL + path, {
    method,
    headers: {
      apikey: serviceKey,
      Authorization: 'Bearer ' + serviceKey,
      'Content-Type': 'application/json',
      ...extra,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(30000),
  });
  const data = await r.json().catch(() => null);
  if (!r.ok) {
    const code = String(data?.code ?? '');
    if (/^PT[0-9]{3}$/.test(code)) throw new Problem(data.message, Number(code.slice(2)));
    if (code === '23505') throw new Problem('This record already exists.', 409);
    // Do not reflect provider keys, database details or upstream URLs.
    throw new Problem(
      'The cloud service could not complete this request. Please try again.',
      r.status === 429 ? 429 : 502,
    );
  }
  return data;
}
export const rpc = (name: string, body: unknown) => platform('/rest/v1/rpc/' + name, 'POST', body);
export async function digest(s: string | Uint8Array) {
  const b = typeof s === 'string' ? new TextEncoder().encode(s) : s;
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new Uint8Array(b)))).map(
    (v) => v.toString(16).padStart(2, '0'),
  ).join('');
}
export function token() {
  return Array.from(crypto.getRandomValues(new Uint8Array(40))).map((v) =>
    v.toString(16).padStart(2, '0')
  ).join('');
}
export async function limit(key: string, maximum: number, seconds = 60) {
  requireValue(
    await rpc('travel_limit', { k: key, maximum, seconds }),
    'Please wait before trying again.',
    429,
  );
}
export async function account(req: Request) {
  const bearer = req.headers.get('Authorization')?.match(/^Bearer ([a-f0-9]{80})$/)?.[1];
  requireValue(bearer, 'Sign in to your travel account first.', 401);
  const rows = await platform(
    '/rest/v1/travel_sessions?select=user_id&token_hash=eq.' + await digest(bearer) +
      '&expires=gt.' + encodeURIComponent(new Date().toISOString()),
  );
  requireValue(rows?.[0], 'Your session expired. Please sign in again.', 401);
  return rows[0].user_id as string;
}
export async function auth(body: any, register: boolean) {
  const handle = String(body.handle ?? '').trim().toLowerCase(), password = body.password;
  requireValue(
    /^[a-z0-9_]{3,32}$/.test(handle),
    'Use a username with 3–32 letters, numbers or underscores.',
  );
  requireValue(
    typeof password === 'string' && password.length >= 8 && password.length <= 256,
    'Use a password with 8–256 characters.',
  );
  // Username-only accounts preserve the existing app contract. These internal identifiers
  // are never presented as verified real email addresses or used to send email.
  const email = handle + '@accounts.seur.invalid';
  if (register) {
    const name = String(body.name ?? '').trim() || handle;
    requireValue(name.length <= 100, 'Display name is too long.');
    const existing = await platform('/rest/v1/travel_profiles?select=id&handle=eq.' + handle);
    requireValue(!existing.length, 'That username is already taken.', 409);
    const r = await fetch(projectURL + '/auth/v1/admin/users', {
      method: 'POST',
      headers: {
        apikey: serviceKey,
        Authorization: 'Bearer ' + serviceKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ email, password, email_confirm: true }),
      signal: AbortSignal.timeout(20000),
    });
    const user = await r.json();
    requireValue(
      r.ok && user.id,
      'Could not create this username. It may already be taken.',
      r.status === 422 ? 409 : 502,
    );
    try {
      await platform('/rest/v1/travel_profiles', 'POST', { id: user.id, handle, name });
    } catch (e) {
      await platform('/auth/v1/admin/users/' + user.id, 'DELETE').catch(() => {});
      throw e;
    }
  }
  const r = await fetch(projectURL + '/auth/v1/token?grant_type=password', {
    method: 'POST',
    headers: { apikey: serviceKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
    signal: AbortSignal.timeout(20000),
  });
  const session = await r.json();
  requireValue(
    r.ok && session.user?.id,
    'Username or password is incorrect.',
    r.status === 429 ? 429 : 401,
  );
  const user = await rpc('travel_user', { x: session.user.id });
  requireValue(user, 'This account is unavailable.', 401);
  const value = token();
  await platform('/rest/v1/travel_sessions', 'POST', {
    token_hash: await digest(value),
    user_id: user.id,
    expires: new Date(Date.now() + 30 * 86400000).toISOString(),
  });
  // Password verification uses Supabase Auth; the app receives its own opaque,
  // immediately revocable session. Supabase refresh tokens never leave this function.
  await fetch(projectURL + '/auth/v1/logout?scope=local', {
    method: 'POST',
    headers: { apikey: serviceKey, Authorization: 'Bearer ' + session.access_token },
  }).catch(() => {});
  return { token: value, user };
}
export async function storage(path: string, method = 'GET', bytes?: Uint8Array) {
  const r = await fetch(
    projectURL + '/storage/v1/object/' + (method === 'GET' ? 'authenticated/' : '') +
      'journey-photos/' + path,
    {
      method,
      headers: {
        apikey: serviceKey,
        Authorization: 'Bearer ' + serviceKey,
        'Content-Type': 'image/jpeg',
        'x-upsert': 'true',
      },
      body: bytes ? new Uint8Array(bytes) : undefined,
      signal: AbortSignal.timeout(20000),
    },
  );
  requireValue(r.ok, 'A trip photo could not be saved or loaded. Please try again.', 502);
  return r;
}
export function encodeBase64(bytes: Uint8Array) {
  let out = '';
  for (let i = 0; i < bytes.length; i += 16384) {
    out += String.fromCharCode(...bytes.subarray(i, i + 16384));
  }
  return btoa(out);
}
