import assert from 'node:assert/strict';
import { activityState, flightChange, sendPush, watches, notificationWorker } from '../functions/travel-api/notifications.ts';
const flight = { ident: 'BA178', status: 'Scheduled', origin: 'JFK', destination: 'LHR', originZone: 'America/New_York', destinationZone: 'Europe/London', scheduledOut: '2026-10-01T22:00:00Z', scheduledIn: '2026-10-02T05:00:00Z', gateOrigin: '4', terminalOrigin: '7' };
Deno.test('Device token rotation preserves an existing Live Activity registration', async () => {
  const names = ['APNS_PRIVATE_KEY_B64','APNS_KEY_ID','APNS_TEAM_ID','APNS_BUNDLE_ID'];
  const old = names.map(n => Deno.env.get(n)), original = globalThis.fetch;
  names.forEach(n => Deno.env.set(n, 'test'));
  const id = '12345678-1234-4234-8234-123456789012'; let patched = false;
  globalThis.fetch = async (_input, init) => {
    if (init?.method === 'PATCH') {
      const body = JSON.parse(String(init.body)); patched = true;
      assert.equal(body.device_token, 'c'.repeat(64)); assert.equal(body.environment, 'production');
      assert.equal('activity_token' in body, false); assert.equal('activity_id' in body, false);
      return Response.json(null);
    }
    return Response.json([{id, activity_token:'b'.repeat(64)}]);
  };
  try { await watches('owner', 'PUT', {id, installationID:id, deviceToken:'c'.repeat(64), environment:'production'}); assert(patched); }
  finally { globalThis.fetch = original; names.forEach((n,i)=>old[i] === undefined ? Deno.env.delete(n) : Deno.env.set(n,old[i]!)); }
});
Deno.test('Live Activity state uses airport-local times and actual flight phases', () => {
  const state = activityState(flight, 123);
  assert.equal(state.departureTime, '18:00'); assert.equal(state.arrivalTime, '06:00'); assert.equal(state.updatedAt, 123); assert.equal(state.phase, 'scheduled');
  assert.equal(activityState({...flight, actualOut: flight.scheduledOut}).phase, 'departed');
  assert.equal(activityState({...flight, actualIn: flight.scheduledIn}).phase, 'arrived');
  assert.equal(activityState({...flight, cancelled: true}).phase, 'cancelled');
});
Deno.test('Flight alerts detect meaningful changes without repeating stable data', () => {
  assert.equal(flightChange(flight, {...flight}), null);
  assert.match(flightChange(flight, {...flight, gateOrigin: '8'})!, /gate 8/);
  assert.match(flightChange(flight, {...flight, cancelled: true})!, /cancelled/);
  assert.match(flightChange(flight, {...flight, actualIn: flight.scheduledIn})!, /arrived/);
  assert.equal(flightChange(flight, {...flight, estimatedOut: '2026-10-01T22:02:00Z'}), null);
  assert.match(flightChange(flight, {...flight, estimatedOut: '2026-10-01T22:15:00Z'})!, /18:15/);
});
Deno.test('Notification boundaries reject malformed device registrations and worker tickets', async () => {
  await assert.rejects(() => watches('user', 'POST', {installationID: 'not-a-uuid'}));
  await assert.rejects(() => notificationWorker('invented-ticket'));
  await assert.rejects(() => sendPush('invalid', 'sandbox', {}));
  await assert.rejects(() => sendPush('a'.repeat(64), 'attacker.example', {}));
});
Deno.test('APNs uses signed token auth, the selected environment and Live Activity topic', async () => {
  const names = ['APNS_PRIVATE_KEY_B64','APNS_KEY_ID','APNS_TEAM_ID','APNS_BUNDLE_ID'];
  const old = names.map(n => Deno.env.get(n)); const fetchOriginal = globalThis.fetch;
  const pair = await crypto.subtle.generateKey({ name:'ECDSA', namedCurve:'P-256' }, true, ['sign','verify']);
  const bytes = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  const raw = Array.from(bytes, b => String.fromCharCode(b)).join('');
  Deno.env.set(names[0], btoa('-----BEGIN PRIVATE KEY-----\n'+btoa(raw)+'\n-----END PRIVATE KEY-----'));
  Deno.env.set(names[1], 'TESTKEY123'); Deno.env.set(names[2], 'TESTTEAM12'); Deno.env.set(names[3], 'com.seurapp.travel');
  globalThis.fetch = async (input, init) => {
    assert(String(input).startsWith('https://api.sandbox.push.apple.com/3/device/'));
    const headers = new Headers(init?.headers); assert.equal(headers.get('apns-topic'), 'com.seurapp.travel.push-type.liveactivity');
    const jwt = headers.get('authorization')!.split(' ')[1], parts = jwt.split('.');
    const signature = Uint8Array.from(atob(parts[2].replace(/-/g,'+').replace(/_/g,'/')), c=>c.charCodeAt(0));
    assert(await crypto.subtle.verify({name:'ECDSA',hash:'SHA-256'}, pair.publicKey, signature, new TextEncoder().encode(parts[0]+'.'+parts[1])));
    assert.equal(JSON.parse(String(init?.body)).aps.event, 'update');
    return new Response(null, {status:200});
  };
  try { assert.equal((await sendPush('a'.repeat(64),'sandbox',{aps:{event:'update'}},true)).ok,true); }
  finally { globalThis.fetch = fetchOriginal; names.forEach((n,i)=>old[i] === undefined ? Deno.env.delete(n) : Deno.env.set(n,old[i]!)); }
});
