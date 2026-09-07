import { day, requireValue } from './validation.ts';
import { digest, platform } from './platform.ts';
import { configured, upstream } from './providers.ts';
export const historyEnabled = () =>
  configured('FLIGHTAWARE_API_KEY') && Deno.env.get('FLIGHTAWARE_HISTORY_ENABLED') === 'true';
const pending = new Map<string, Promise<any>>();
async function fetchFlight(path: string, params: Record<string, string> = {}, ttl = 60) {
  requireValue(
    configured('FLIGHTAWARE_API_KEY'),
    'Live flight data is not connected yet. Your saved schedule is still available.',
    503,
  );
  const url = 'https://aeroapi.flightaware.com/aeroapi' + path + '?' + new URLSearchParams(params),
    key = await digest(url);
  if (pending.has(key)) return pending.get(key);
  const job = (async () => {
    const cached = await platform(
      '/rest/v1/travel_provider_cache?select=value&key=eq.' + key + '&expires=gt.' +
        encodeURIComponent(new Date().toISOString()),
    );
    if (cached[0]) return cached[0].value;
    const d = await upstream(url, { 'x-apikey': Deno.env.get('FLIGHTAWARE_API_KEY')! });
    d._aurumFetchedAt = Date.now() / 1000;
    await platform('/rest/v1/travel_provider_cache', 'POST', {
      key,
      value: d,
      expires: new Date(Date.now() + ttl * 1000).toISOString(),
    }, { Prefer: 'resolution=merge-duplicates' });
    return d;
  })();
  pending.set(key, job);
  try {
    return await job;
  } finally {
    pending.delete(key);
  }
}
export function localDay(r: any) {
  const t = r.scheduled_out || r.scheduled_off;
  if (!t) return null;
  try {
    return new Intl.DateTimeFormat('en-CA', {
      timeZone: r.origin?.timezone || 'UTC',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(new Date(t));
  } catch {
    return day(t.slice(0, 10)) ? t.slice(0, 10) : null;
  }
}
export function normalize(r: any) {
  const a = r.origin ?? {},
    b = r.destination ?? {},
    v: any = {
      id: r.fa_flight_id ?? '',
      ident: r.ident_iata || r.ident || '',
      status: r.status || 'Status not reported',
      cancelled: !!r.cancelled,
      diverted: !!r.diverted,
      origin: a.code_iata || a.code || '',
      destination: b.code_iata || b.code || '',
      originName: a.name || '',
      destinationName: b.name || '',
      originZone: a.timezone || 'UTC',
      destinationZone: b.timezone || 'UTC',
    };
  const fields: Record<string, string> = {
    scheduledOut: 'scheduled_out',
    estimatedOut: 'estimated_out',
    actualOut: 'actual_out',
    scheduledIn: 'scheduled_in',
    estimatedIn: 'estimated_in',
    actualIn: 'actual_in',
    scheduledOff: 'scheduled_off',
    actualOff: 'actual_off',
    scheduledOn: 'scheduled_on',
    actualOn: 'actual_on',
    departureDelay: 'departure_delay',
    arrivalDelay: 'arrival_delay',
    gateOrigin: 'gate_origin',
    gateDestination: 'gate_destination',
    terminalOrigin: 'terminal_origin',
    terminalDestination: 'terminal_destination',
    baggageClaim: 'baggage_claim',
    aircraft: 'aircraft_type',
    registration: 'registration',
    inboundID: 'inbound_fa_flight_id',
  };
  for (const [k, f] of Object.entries(fields)) if (r[f] != null) v[k] = r[f];
  return v;
}
const shift = (d: string, n: number) =>
  new Date(Date.parse(d) + n * 86400000).toISOString().slice(0, 10);
export async function flightFeed(ident: string, date: string, history = false) {
  ident = ident.replace(/\s/g, '').toUpperCase();
  requireValue(
    /^[A-Z0-9]{2,3}\d{1,4}[A-Z]?$/.test(ident),
    'Enter an airline code and flight number, for example BA178.',
  );
  requireValue(day(date), 'Choose a valid departure date.');
  const today = new Date().toISOString().slice(0, 10), historical = date < shift(today, -9);
  if (history) {
    requireValue(
      historyEnabled(),
      'Delay history requires a flight-data plan with historical access.',
      503,
    );
    const end = date < today ? date : today,
      start = shift(end, -7),
      d = await fetchFlight('/history/flights/' + ident, { start, end, max_pages: '1' }, 3600);
    return {
      flights: (d.flights ?? []).filter((v: any) =>
        v.actual_in && localDay(v) && localDay(v)! >= start && localDay(v)! < end
      ).map(normalize),
      fetchedAt: d._aurumFetchedAt,
      historyEnabled: true,
      message:
        'A sample of completed departures in the preceding seven days. Limited to one provider page; not a prediction.',
    };
  }
  requireValue(
    !historical || historyEnabled(),
    'This flight needs historical data access. View its saved schedule until history is enabled.',
    503,
  );
  if (date > shift(today, 2)) {
    return {
      flights: [],
      fetchedAt: Date.now() / 1000,
      historyEnabled: historyEnabled(),
      message:
        'Live tracking usually becomes available closer to departure. Your saved schedule is shown below.',
    };
  }
  const d = await fetchFlight((historical ? '/history/flights/' : '/flights/') + ident, {
    start: shift(date, -1),
    end: shift(date, 2),
    max_pages: '1',
  });
  const flights = (d.flights ?? []).filter((v: any) => localDay(v) === date).map(normalize);
  return {
    flights,
    fetchedAt: d._aurumFetchedAt,
    historyEnabled: historyEnabled(),
    message: flights.length
      ? ''
      : 'No matching departure was returned for this local date. Check the flight number, operating airline and date.',
  };
}
export async function flightPosition(id: string) {
  requireValue(/^[A-Za-z0-9_-]{5,180}$/.test(id), 'Invalid flight identifier.');
  const d = await fetchFlight('/flights/' + id + '/position'), p = d.last_position;
  requireValue(
    p && typeof p.latitude === 'number' && typeof p.longitude === 'number' &&
      Math.abs(p.latitude) <= 90 && Math.abs(p.longitude) <= 180,
    'The provider has not reported a position for this flight.',
    503,
  );
  return {
    latitude: p.latitude,
    longitude: p.longitude,
    timestamp: p.timestamp,
    altitude: p.altitude,
    groundspeed: p.groundspeed,
    heading: p.heading,
  };
}
