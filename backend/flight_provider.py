"""AeroAPI adapter. Bounded, cached, server-only calls; no fabricated flight status."""
import datetime as dt
import os
import re
import threading
import time
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
from urllib.parse import urlencode, quote
try:
    from .providers import ProviderError, request_json
except ImportError:
    from providers import ProviderError, request_json

_cache = {}
_lock = threading.Lock()

def connected():
    return bool(os.getenv('FLIGHTAWARE_API_KEY'))

def history_enabled():
    return connected() and os.getenv('FLIGHTAWARE_HISTORY_ENABLED', '').lower() == 'true'

def fetch(path, query=None, ttl=60):
    key = os.getenv('FLIGHTAWARE_API_KEY', '')
    if not key:
        raise ProviderError('Live flight data is not connected yet. Your saved schedule is still available.')
    url = 'https://aeroapi.flightaware.com/aeroapi' + path + ('?' + urlencode(query) if query else '')
    cache_key = (key, url)
    with _lock:
        cached = _cache.get(cache_key)
        if cached and time.monotonic() - cached[0] < ttl:
            return cached[1]
        # Serialize upstream requests to avoid concurrent cache misses and quota bursts.
        value = request_json(url, headers={'x-apikey': key, 'Accept': 'application/json'}, timeout=12)
        value['_aurumFetchedAt'] = time.time()
        if len(_cache) >= 256:
            _cache.clear()
        _cache[cache_key] = (time.monotonic(), value)
        return value

def validate(ident, day):
    ident = re.sub(r'\s+', '', ident).upper() if isinstance(ident, str) else ''
    if not re.fullmatch(r'[A-Z0-9]{2,3}\d{1,4}[A-Z]?', ident):
        raise ProviderError('Enter the airline code and flight number, for example BA178.', 400)
    try:
        date = dt.date.fromisoformat(day)
    except (ValueError, TypeError):
        raise ProviderError('Choose a valid departure date.', 400) from None
    return ident, date

def parse(value):
    try:
        return dt.datetime.fromisoformat(value.replace('Z', '+00:00'))
    except (ValueError, AttributeError):
        return None

def local_day(row):
    value = parse(row.get('scheduled_out')) or parse(row.get('scheduled_off'))
    if not value:
        return None
    zone = (row.get('origin') or {}).get('timezone')
    try:
        return value.astimezone(ZoneInfo(zone)).date() if zone else value.date()
    except (ZoneInfoNotFoundError, TypeError):
        return value.date()

def normalized(row):
    origin, dest = row.get('origin') or {}, row.get('destination') or {}
    result = {'id': str(row.get('fa_flight_id') or ''), 'ident': row.get('ident_iata') or row.get('ident') or '',
              'status': row.get('status') or 'Status not reported', 'cancelled': bool(row.get('cancelled')), 'diverted': bool(row.get('diverted')),
              'origin': origin.get('code_iata') or origin.get('code') or '', 'destination': dest.get('code_iata') or dest.get('code') or '',
              'originName': origin.get('name') or '', 'destinationName': dest.get('name') or '',
              'originZone': origin.get('timezone') or 'UTC', 'destinationZone': dest.get('timezone') or 'UTC'}
    fields = {'scheduledOut':'scheduled_out','estimatedOut':'estimated_out','actualOut':'actual_out',
              'scheduledIn':'scheduled_in','estimatedIn':'estimated_in','actualIn':'actual_in',
              'scheduledOff':'scheduled_off','estimatedOff':'estimated_off','actualOff':'actual_off','scheduledOn':'scheduled_on','estimatedOn':'estimated_on','actualOn':'actual_on',
              'departureDelay':'departure_delay','arrivalDelay':'arrival_delay','gateOrigin':'gate_origin','gateDestination':'gate_destination',
              'terminalOrigin':'terminal_origin','terminalDestination':'terminal_destination','baggageClaim':'baggage_claim',
              'aircraft':'aircraft_type','registration':'registration','inboundID':'inbound_fa_flight_id'}
    for target, source in fields.items():
        if row.get(source) is not None:
            result[target] = row[source]
    return result

def status(ident, day):
    ident, date = validate(ident, day)
    today = dt.datetime.now(dt.timezone.utc).date()
    historical = date < today - dt.timedelta(days=9)
    if historical and not history_enabled():
        raise ProviderError('This flight needs historical data access. Enable a flight-data plan with history, or view its saved schedule.')
    if date > today + dt.timedelta(days=2):
        return {'flights': [], 'fetchedAt': time.time(), 'historyEnabled': history_enabled(), 'message': 'Live tracking usually becomes available closer to departure. Your saved schedule is shown below.'}
    path = ('/history/flights/' if historical else '/flights/') + quote(ident, safe='')
    data = fetch(path, {'start': (date-dt.timedelta(days=1)).isoformat(), 'end': (date+dt.timedelta(days=2)).isoformat(), 'max_pages': 1})
    flights = [normalized(row) for row in data.get('flights', []) if local_day(row) == date]
    return {'flights': flights, 'fetchedAt': data['_aurumFetchedAt'], 'historyEnabled': history_enabled(),
            'message': '' if flights else 'No matching departure was returned for this local date. Check the flight number, operating airline and date.'}

def history(ident, day):
    ident, date = validate(ident, day)
    if not history_enabled():
        raise ProviderError('Delay history requires a flight-data plan with historical access.')
    end = min(date, dt.datetime.now(dt.timezone.utc).date())
    start = end - dt.timedelta(days=7)
    data = fetch('/history/flights/' + quote(ident, safe=''), {'start':start.isoformat(), 'end':end.isoformat(), 'max_pages':1}, ttl=3600)
    rows = [normalized(row) for row in data.get('flights', []) if row.get('actual_in') and local_day(row) and start <= local_day(row) < end]
    return {'flights': rows, 'fetchedAt': data['_aurumFetchedAt'], 'historyEnabled': True,
            'message': 'A sample of completed departures in the preceding seven days. Limited to one provider page; not a prediction.'}

def position(identifier):
    if not isinstance(identifier, str) or not re.fullmatch(r'[A-Za-z0-9_-]{5,180}', identifier):
        raise ProviderError('Invalid flight identifier.', 400)
    data = fetch('/flights/' + quote(identifier, safe='') + '/position')
    p = data.get('last_position') or {}
    lat, lon = p.get('latitude'), p.get('longitude')
    if not isinstance(lat, (int,float)) or not isinstance(lon, (int,float)) or not (-90 <= lat <= 90 and -180 <= lon <= 180):
        raise ProviderError('The provider has not reported a position for this flight.')
    return {'latitude':lat, 'longitude':lon, 'timestamp':p.get('timestamp'), 'altitude':p.get('altitude'), 'groundspeed':p.get('groundspeed'), 'heading':p.get('heading')}
