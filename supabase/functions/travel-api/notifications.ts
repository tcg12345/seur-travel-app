import { day, object, requireValue, uuid } from './validation.ts';
import { limit, platform, rpc } from './platform.ts';
import { flightFeed } from './flights.ts';

export const pushConfigured = () => !!(Deno.env.get('APNS_PRIVATE_KEY_B64') && Deno.env.get('APNS_KEY_ID') && Deno.env.get('APNS_TEAM_ID') && Deno.env.get('APNS_BUNDLE_ID'));
const seconds = (v: unknown) => typeof v === 'string' && Number.isFinite(Date.parse(v)) ? Date.parse(v) / 1000 : 0;
const clock = (value: unknown, zone: string) => {
  if (!seconds(value)) return '—';
  try { return new Intl.DateTimeFormat('en-GB', { timeZone: zone || 'UTC', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(new Date(String(value))); } catch { return '—'; }
};
export function activityState(f: any, now = Date.now() / 1000) {
  const out = f.actualOut || f.estimatedOut || f.scheduledOut, into = f.actualIn || f.estimatedIn || f.scheduledIn;
  return { status: String(f.status).slice(0, 80), departure: seconds(out), arrival: seconds(into), departureTime: clock(out, f.originZone), arrivalTime: clock(into, f.destinationZone), gate: String(f.gateOrigin || '').slice(0, 30), terminal: String(f.terminalOrigin || '').slice(0, 30), delayMinutes: Math.max(0, Math.round((Number(f.departureDelay) || 0) / 60)), phase: f.cancelled ? 'cancelled' : f.actualIn ? 'arrived' : f.actualOut ? 'departed' : 'scheduled', updatedAt: now };
}
export function flightChange(before: any, after: any): string | null {
  if (!before.cancelled && after.cancelled) return 'Your flight has been cancelled. Check with your airline.';
  if (!before.diverted && after.diverted) return 'Your flight has been diverted. Check the latest airline information.';
  if (!before.actualIn && after.actualIn) return 'Your flight has arrived at ' + after.destination + (after.gateDestination ? ', gate ' + after.gateDestination : '') + '.';
  if (!before.actualOut && after.actualOut) return 'Your flight has departed from ' + after.origin + '.';
  if (after.gateOrigin && before.gateOrigin !== after.gateOrigin) return 'Departure gate ' + after.gateOrigin + (after.terminalOrigin ? ' · Terminal ' + after.terminalOrigin : '') + '.';
  if (after.terminalOrigin && before.terminalOrigin !== after.terminalOrigin) return 'Departure terminal is now ' + after.terminalOrigin + '.';
  const previous = seconds(before.estimatedOut || before.scheduledOut), next = seconds(after.estimatedOut || after.scheduledOut);
  if (previous && next && Math.abs(next - previous) >= 300) return 'Expected departure is now ' + clock(after.estimatedOut || after.scheduledOut, after.originZone) + ' local time.';
  if (after.gateDestination && before.gateDestination !== after.gateDestination) return 'Arrival gate ' + after.gateDestination + '.';
  return null;
}
function b64(bytes: Uint8Array) { let raw = ''; for (const b of bytes) raw += String.fromCharCode(b); return btoa(raw).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_'); }
let signed: { value: string; until: number } | null = null;
export async function apnsJWT() {
  if (signed && signed.until > Date.now()) return signed.value;
  requireValue(pushConfigured(), 'Flight notifications are not connected yet.', 503);
  const pem = atob(Deno.env.get('APNS_PRIVATE_KEY_B64')!);
  const raw = atob(pem.replace(/-----[^-]+-----/g, '').replace(/\s/g, ''));
  const key = await crypto.subtle.importKey('pkcs8', Uint8Array.from(raw, c => c.charCodeAt(0)), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const encoder = new TextEncoder(), part = (v: unknown) => b64(encoder.encode(JSON.stringify(v)));
  const input = part({ alg: 'ES256', kid: Deno.env.get('APNS_KEY_ID') }) + '.' + part({ iss: Deno.env.get('APNS_TEAM_ID'), iat: Math.floor(Date.now() / 1000) });
  const signature = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, encoder.encode(input)));
  signed = { value: input + '.' + b64(signature), until: Date.now() + 45 * 60000 }; return signed.value;
}
export async function sendPush(token: string, environment: string, payload: unknown, activity = false, collapse = '') {
  requireValue(/^[a-f0-9]{32,512}$/.test(token), 'Invalid notification token.');
  requireValue(['sandbox', 'production'].includes(environment), 'Invalid notification environment.');
  const host = environment === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
  const response = await fetch('https://' + host + '/3/device/' + token, { method: 'POST', headers: {
    authorization: 'bearer ' + await apnsJWT(), 'apns-topic': Deno.env.get('APNS_BUNDLE_ID')! + (activity ? '.push-type.liveactivity' : ''),
    'apns-push-type': activity ? 'liveactivity' : 'alert', 'apns-priority': activity ? '5' : '10',
    'apns-expiration': String(Math.floor(Date.now() / 1000) + 900), ...(collapse ? { 'apns-collapse-id': collapse } : {}),
  }, body: JSON.stringify(payload), signal: AbortSignal.timeout(10000) });
  if (response.ok) return { ok: true, invalid: false };
  const value = await response.json().catch(() => ({}));
  // Log only APNs error codes; never log device tokens, keys or travel data.
  console.warn('APNs delivery', response.status, value.reason || 'unknown');
  return { ok: false, invalid: ['BadDeviceToken', 'Unregistered', 'DeviceTokenNotForTopic'].includes(value.reason) };
}

export async function watches(actor: string, method: string, body: any, sessionHash = '') {
  requireValue(object(body) && uuid(body.installationID), 'Invalid device registration.');
  const base = '/rest/v1/travel_flight_watches?user_id=eq.' + actor + '&installation_id=eq.' + body.installationID.toLowerCase();
  if (method === 'DELETE') {
    if (body.id) requireValue(uuid(body.id), 'Invalid flight notification.');
    await platform(base + (body.id ? '&id=eq.' + body.id.toLowerCase() : ''), 'DELETE'); return { ok: true };
  }
  if (method === 'GET') return await platform(base + '&enabled=eq.true&expires_at=gt.' + encodeURIComponent(new Date().toISOString()) + '&select=id,flight_id,activity_id');
  requireValue(pushConfigured(), 'Flight notifications are not connected yet.', 503);
  requireValue(/^[a-f0-9]{32,512}$/.test(body.deviceToken || ''), 'Enable notifications on this iPhone first.');
  requireValue(['sandbox','production'].includes(body.environment), 'Invalid notification environment.');
  if (body.activityToken) requireValue(/^[a-f0-9]{32,512}$/.test(body.activityToken) && typeof body.activityID === 'string' && body.activityID.length <= 100, 'Invalid Live Activity registration.');
  if (body.id) {
    requireValue(uuid(body.id), 'Invalid flight notification.');
    const rows = await platform(base + '&id=eq.' + body.id.toLowerCase());
    requireValue(rows[0], 'This flight is no longer followed.', 404);
    await platform(base + '&id=eq.' + body.id.toLowerCase(), 'PATCH', { device_token: body.deviceToken, environment: body.environment, ...('activityToken' in body ? { activity_token: body.activityToken || null, activity_id: body.activityID || null } : {}), updated_at: new Date().toISOString() });
    return { id: rows[0].id };
  }
  requireValue(typeof body.ident === 'string' && body.ident.length <= 10 && day(body.day) && typeof body.flightID === 'string' && body.flightID.length <= 180, 'Choose a live departure first.');
  await limit('push-follow:' + actor, 10);
  const existing = await platform(base + '&enabled=eq.true&select=id,flight_id');
  requireValue(existing.length < 10 || existing.some((r: any) => r.flight_id === body.flightID), 'Follow up to ten flights on this device.', 409);
  const feed = await flightFeed(body.ident, body.day), snapshot = feed.flights.find((f: any) => f.id === body.flightID);
  requireValue(snapshot, 'That departure is no longer available. Refresh your flight.', 409);
  const departure = seconds(snapshot.scheduledOut || snapshot.scheduledOff);
  requireValue(departure > Date.now() / 1000 - 24 * 3600 && !snapshot.actualIn && !snapshot.cancelled, 'Follow an upcoming or active flight.', 409);
  const previous = existing.find((r: any) => r.flight_id === body.flightID);
  const rows = await platform('/rest/v1/travel_flight_watches?on_conflict=user_id,installation_id,flight_id', 'POST', {
    ...(previous ? { id: previous.id } : {}), user_id: actor, session_hash: sessionHash, installation_id: body.installationID.toLowerCase(), device_token: body.deviceToken,
    environment: body.environment, flight_id: snapshot.id, ident: body.ident, departure_day: body.day, snapshot,
    enabled: true, next_check: new Date().toISOString(), expires_at: new Date((departure + 48 * 3600) * 1000).toISOString(), updated_at: new Date().toISOString(),
  }, { Prefer: 'resolution=merge-duplicates,return=representation' });
  return { id: rows[0].id };
}

export async function notificationWorker(ticket: unknown) {
  requireValue(uuid(ticket) && await rpc('travel_push_claim_job', { ticket }), 'Invalid worker ticket.', 401);
  requireValue(pushConfigured(), 'Push delivery is unavailable.', 503);
  const rows = await rpc('travel_push_claim_watches', {}), feeds = new Map<string, any>();
  let checked = 0, sent = 0, failed = 0;
  for (const row of rows) {
    try {
      const key = row.ident + ':' + row.departure_day;
      if (!feeds.has(key)) { await limit('push-provider-global', 120, 3600); feeds.set(key, await flightFeed(row.ident, row.departure_day)); }
      const flight = feeds.get(key).flights.find((f: any) => f.id === row.flight_id);
      if (!flight) continue;
      checked++;
      const now = Math.floor(Date.now() / 1000), state = activityState(flight, now), done = state.phase === 'arrived' || state.phase === 'cancelled';
      const departure = seconds(flight.estimatedOut || flight.scheduledOut), reminder = !row.reminder_sent && !flight.actualOut && !done && departure > now && departure - now <= 2 * 3600;
      const change = flightChange(row.snapshot, flight);
      let delivered = true, activityDelivered = true, invalidDevice = false;
      if (change || reminder) {
        const result = await sendPush(row.device_token, row.environment, { aps: { alert: { title: flight.ident + ' · ' + flight.origin + ' → ' + flight.destination, body: change || 'Your flight is expected to depart within two hours. Check your gate and airline updates.' }, sound: 'default', 'thread-id': row.id }, flightWatchID: row.id }, false, row.id);
        delivered = result.ok; invalidDevice = result.invalid; if (result.ok) sent++; else failed++;
      }
      let invalidActivity = false;
      if (row.activity_token) {
        const result = await sendPush(row.activity_token, row.environment, { aps: { timestamp: now, event: done ? 'end' : 'update', 'content-state': state, 'stale-date': now + 20 * 60, ...(done ? { 'dismissal-date': now + 30 * 60 } : {}) } }, true, row.id);
        invalidActivity = result.invalid; if (result.ok) sent++; else failed++;
        activityDelivered = result.ok || result.invalid;
      }
      await platform('/rest/v1/travel_flight_watches?id=eq.' + row.id, 'PATCH', {
        ...(delivered ? { snapshot: flight, reminder_sent: row.reminder_sent || reminder } : {}),
        enabled: !invalidDevice && !(done && delivered && activityDelivered), ...(invalidActivity ? { activity_token: null, activity_id: null } : {}),
        next_check: new Date((now + (departure - now > 6 * 3600 ? 1800 : 300)) * 1000).toISOString(), updated_at: new Date().toISOString(),
      });
    } catch { failed++; /* Claim lease backs off failures without exposing tokens. */ }
  }
  return { checked, sent, failed };
}
