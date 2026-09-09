import { digest, platform, projectURL, rpc, token } from './platform.ts';
import { Problem, requireValue } from './validation.ts';

const serviceKey = () => Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
export function emailAddress(value: unknown): string {
  requireValue(typeof value === 'string', 'Enter your email address.');
  const email = value.trim().toLowerCase();
  requireValue(email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) && !email.endsWith('.invalid'), 'Enter a valid email address.');
  return email;
}
export function passwordValue(value: unknown): string {
  requireValue(typeof value === 'string' && value.length >= 8 && value.length <= 256, 'Use a password with 8–256 characters.');
  return value;
}
export function verifiedUser(user: any): boolean {
  return typeof user?.id === 'string' && !!user.email_confirmed_at && typeof user.email === 'string' && !user.email.toLowerCase().endsWith('.invalid');
}
async function authRequest(path: string, body?: unknown) {
  const response = await fetch(projectURL + '/auth/v1/' + path, {
    method: body === undefined ? 'GET' : 'POST',
    headers: { apikey: serviceKey(), 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(20000),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const code = data.error_code ?? data.code;
    if (response.status === 429) throw new Problem('Please wait a moment before trying again.',429);
    if (code === 'email_not_confirmed') throw new Problem('Verify your email first. You can resend the confirmation below.',403);
    if (code === 'email_address_not_authorized' || code === 'unexpected_failure') throw new Problem('Email delivery is not available yet. Please try another sign-in method.',503);
    if (code === 'weak_password') throw new Problem('Choose a stronger password with at least 8 characters.',400);
    if (path.startsWith('verify')) throw new Problem('That code is invalid or expired. Request a new one and try again.',400);
    if (path.startsWith('token')) throw new Problem('Could not sign in. Check your details and try again.',401);
    throw new Problem('Could not complete account setup. Please try again.',400);
  }
  return data;
}
export async function authOptions() {
  const settings = await authRequest('settings');
  return { apple: settings.external?.apple === true, google: settings.external?.google === true,
    email: settings.external?.email === true && settings.mailer_autoconfirm === false, minimumPasswordLength: 8 };
}
async function profileFor(user: any, providedName?: string) {
  let profile = await rpc('travel_user', {x:user.id});
  if (profile) return profile;
  const metadata = user.user_metadata ?? {};
  // Metadata provides display values only. Identity is always the verified Auth user ID.
  const name = String(providedName || metadata.name || metadata.full_name || 'Traveler').trim().slice(0,100) || 'Traveler';
  const proposed = typeof metadata.handle === 'string' && /^[a-z0-9_]{3,32}$/.test(metadata.handle) ? metadata.handle : '';
  for (let attempt = 0; attempt < 3; attempt++) {
    const handle = attempt === 0 && proposed ? proposed : 'traveler_' + token().slice(0,12);
    try { await platform('/rest/v1/travel_profiles','POST',{id:user.id,handle,name}); }
    catch (e) {
      profile = await rpc('travel_user',{x:user.id});
      if (profile) return profile;
      if (e instanceof Problem && e.status === 409) continue;
      throw e;
    }
    return await rpc('travel_user',{x:user.id});
  }
  throw new Problem('Could not finish your profile. Please sign in again.',409);
}
async function finish(session: any, name?: string) {
  try {
    requireValue(session.access_token && verifiedUser(session.user), 'Verify your email before signing in.',403);
    const user = await profileFor(session.user,name), value = token();
    await platform('/rest/v1/travel_sessions','POST',{token_hash:await digest(value),user_id:user.id,expires:new Date(Date.now()+30*86400000).toISOString()});
    return {token:value,user};
  } finally {
    // The app keeps only an opaque revocable Seur session, not provider/refresh tokens.
    if (session.access_token) await fetch(projectURL+'/auth/v1/logout?scope=local',{method:'POST',headers:{apikey:serviceKey(),Authorization:'Bearer '+session.access_token},signal:AbortSignal.timeout(5000)}).catch(()=>{});
  }
}
export async function accountAuth(action: string, body: any) {
  if (action === 'email/signup') {
    const email=emailAddress(body.email), password=passwordValue(body.password);
    requireValue(typeof body.name==='string' && body.name.trim().length>0 && body.name.length<=100,'Enter your name.');
    requireValue(typeof body.handle==='string' && /^[a-z0-9_]{3,32}$/.test(body.handle),'Choose a username with 3–32 letters, numbers or underscores.');
    requireValue((await authOptions()).email,'Email signup is not available yet. Please try another sign-in method.',503);
    const response=await authRequest('signup',{email,password,data:{name:body.name.trim(),handle:body.handle}});
    // Never issue a Seur session here, even if a configuration change auto-confirms signup.
    if (response.access_token) await fetch(projectURL+'/auth/v1/logout?scope=local',{method:'POST',headers:{apikey:serviceKey(),Authorization:'Bearer '+response.access_token}}).catch(()=>{});
    return {pending:true,email};
  }
  if (action === 'email/login') return await finish(await authRequest('token?grant_type=password',{email:emailAddress(body.email),password:passwordValue(body.password)}));
  if (action === 'email/verify') {
    requireValue(typeof body.code==='string' && /^[0-9]{6,10}$/.test(body.code),'Enter the verification code from your email.');
    return await finish(await authRequest('verify',{email:emailAddress(body.email),token:body.code,type:'signup'}));
  }
  if (action === 'email/resend') {
    await authRequest('resend',{email:emailAddress(body.email),type:'signup'});
    return {ok:true};
  }
  if (action === 'apple') {
    requireValue(typeof body.idToken==='string' && body.idToken.length>=100 && body.idToken.length<=12000,'Apple did not return a valid sign-in token.');
    requireValue(typeof body.nonce==='string' && /^[A-Za-z0-9_-]{32,128}$/.test(body.nonce),'Start Apple sign-in again.');
    requireValue((await authOptions()).apple,'Apple sign-in is not available yet.',503);
    return await finish(await authRequest('token?grant_type=id_token',{provider:'apple',id_token:body.idToken,nonce:body.nonce}),typeof body.name==='string'?body.name.slice(0,100):undefined);
  }
  if (action === 'google/start') {
    requireValue((await authOptions()).google,'Google sign-in is not available yet.',503);
    requireValue(typeof body.challenge==='string' && /^[A-Za-z0-9_-]{43}$/.test(body.challenge),'Start Google sign-in again.');
    const url=new URL(projectURL+'/auth/v1/authorize');
    url.search=new URLSearchParams({provider:'google',redirect_to:'seur://auth/callback',code_challenge:body.challenge,code_challenge_method:'s256',scopes:'openid email profile',prompt:'select_account'}).toString();
    return {url:url.href};
  }
  if (action === 'google/exchange') {
    requireValue(typeof body.code==='string' && body.code.length>=10 && body.code.length<=2000,'Google did not return a valid authorization code.');
    requireValue(typeof body.verifier==='string' && /^[A-Za-z0-9._~-]{43,128}$/.test(body.verifier),'Start Google sign-in again.');
    return await finish(await authRequest('token?grant_type=pkce',{auth_code:body.code,code_verifier:body.verifier}));
  }
  throw new Problem('Account action not found.',404);
}
