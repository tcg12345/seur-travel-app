"""Aurum WSGI API. SQLite persistence; bearer sessions; explicit owner/recipient ACLs."""
import base64
import copy
from contextlib import closing
import datetime
import hashlib
import hmac
import html
import io
import json
import math
import os
from pathlib import Path
import re
import secrets
import sqlite3
import threading
import time
import urllib.parse
import uuid
from wsgiref.simple_server import make_server, WSGIRequestHandler
from socketserver import ThreadingMixIn
from wsgiref.simple_server import WSGIServer

try:
    from . import providers, flight_provider
except ImportError:
    import providers, flight_provider

ROOT = Path(__file__).resolve().parent

def load_env():
    file = ROOT / '.env'
    if file.exists():
        for line in file.read_text().splitlines():
            key, separator, value = line.partition('=')
            if separator and key.strip() and not key.lstrip().startswith('#'):
                os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))
load_env()

class APIError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status

SCHEMA = '''
PRAGMA foreign_keys=ON;
CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY, handle TEXT UNIQUE NOT NULL, name TEXT NOT NULL, password TEXT NOT NULL, created REAL NOT NULL);
CREATE TABLE IF NOT EXISTS sessions(token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, expires REAL NOT NULL);
CREATE TABLE IF NOT EXISTS friendships(a TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, b TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, requester TEXT NOT NULL REFERENCES users(id), status TEXT NOT NULL CHECK(status IN ('pending','accepted')), PRIMARY KEY(a,b), CHECK(a < b));
CREATE TABLE IF NOT EXISTS documents(id TEXT PRIMARY KEY, owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, body TEXT NOT NULL, visibility TEXT NOT NULL CHECK(visibility IN ('private','friends','public')), revision INTEGER NOT NULL DEFAULT 1, updated REAL NOT NULL);
CREATE TABLE IF NOT EXISTS links(token TEXT PRIMARY KEY, document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE, created REAL NOT NULL);
CREATE TABLE IF NOT EXISTS conversations(id TEXT PRIMARY KEY, name TEXT NOT NULL, creator_id TEXT NOT NULL REFERENCES users(id), created REAL NOT NULL);
CREATE TABLE IF NOT EXISTS members(conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, PRIMARY KEY(conversation_id,user_id));
CREATE TABLE IF NOT EXISTS messages(id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE, sender_id TEXT NOT NULL REFERENCES users(id), text TEXT NOT NULL, document_id TEXT REFERENCES documents(id) ON DELETE SET NULL, created REAL NOT NULL);
CREATE TABLE IF NOT EXISTS grants(document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, PRIMARY KEY(document_id,user_id));
CREATE INDEX IF NOT EXISTS messages_conversation ON messages(conversation_id,created);
CREATE INDEX IF NOT EXISTS documents_owner ON documents(owner_id);
CREATE INDEX IF NOT EXISTS sessions_expiry ON sessions(expires);
'''

CATEGORIES = {'restaurant','attraction','hotel','museum','park','monument','shopping','entertainment','bar','cafe','beach','spa','landmark','other'}

def require(condition, message, status=400):
    if not condition:
        raise APIError(status, message)

def valid_id(value):
    try:
        uuid.UUID(value)
        return True
    except (ValueError, TypeError, AttributeError):
        return False

def valid_day(value):
    try:
        return isinstance(value, str) and datetime.date.fromisoformat(value).isoformat() == value
    except ValueError:
        return False

def finite(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)

def text(value, name, limit=10000, optional=False):
    require(isinstance(value, str) and len(value) <= limit and (optional or value.strip()), f'Invalid {name}.')

EVENT_KINDS = {'place':'Restaurant or activity', 'meeting':'Meeting', 'appointment':'Appointment', 'conference':'Conference', 'celebration':'Celebration', 'concert':'Concert', 'performance':'Theatre & performance', 'sport':'Sporting event', 'tour':'Tour & excursion', 'transfer':'Car & transfer', 'train':'Train', 'ferry':'Boat & ferry', 'shopping':'Shopping', 'wellness':'Wellness', 'freeTime':'Free time', 'custom':'Custom event'}

def validate_place(place, allow_empty_name=False):
    require(isinstance(place, dict), 'Invalid place.')
    text(place.get('id'), 'place ID', 500)
    text(place.get('name'), 'place name', 500, allow_empty_name)
    require(place.get('category') in CATEGORIES, 'Invalid place category.')
    for key in ('city','address','phone','website','source','overview'):
        text(place.get(key, ''), key, 15000, True)
    lat, lon = place.get('latitude'), place.get('longitude')
    if lat is not None or lon is not None:
        require(finite(lat) and finite(lon) and -90 <= lat <= 90 and -180 <= lon <= 180, 'Invalid coordinates.')
    if place.get('rating') is not None:
        require(finite(place['rating']) and 0 <= place['rating'] <= 5, 'Invalid provider rating.')

def validate_money(cost):
    if cost is None:
        return
    require(isinstance(cost, dict) and finite(cost.get('amount')) and 0 <= cost['amount'] <= 1_000_000_000, 'Invalid price.')
    require(isinstance(cost.get('currency'), str) and re.fullmatch(r'[A-Z]{3}', cost['currency']), 'Invalid currency.')

def validate_document(d):
    require(isinstance(d, dict) and valid_id(d.get('id')), 'Invalid journey ID.')
    require(d.get('kind') in ('itinerary','trip','journey'), 'Invalid journey type.')
    require(d.get('visibility') in ('private','friends','public'), 'Invalid audience.')
    text(d.get('title'), 'title', 200)
    text(d.get('description', ''), 'description', 20000, True)
    text(d.get('destination', ''), 'destination', 1000, True)
    require(d.get('dateMode') in ('dates','nights'), 'Invalid date mode.')
    for key in ('startDate','endDate'):
        require(d.get(key) is None or valid_day(d[key]), 'Invalid journey date.')
    if d.get('startDate') and d.get('endDate'):
        require(d['endDate'] >= d['startDate'], 'Journey end precedes start.')
    require(finite(d.get('updatedAt')), 'Invalid updated timestamp.')
    for key, limit in [('stops',40),('events',2000),('hotels',200),('flights',200),('places',500)]:
        require(isinstance(d.get(key), list) and len(d[key]) <= limit, f'Too many or invalid {key}.')
        require(all(isinstance(item, dict) and valid_id(item.get('id')) for item in d[key]), f'Invalid {key} identifiers.')
        require(len({item['id'] for item in d[key]}) == len(d[key]), f'Duplicate {key} identifiers.')
    stops = {}
    previous = None
    for stop in d['stops']:
        text(stop.get('name'), 'destination name', 500)
        require(isinstance(stop.get('nights'), int) and 1 <= stop['nights'] <= 365 and valid_day(stop.get('arrival')), 'Invalid destination dates or nights.')
        if d['dateMode'] == 'dates' and previous:
            require(datetime.date.fromisoformat(stop['arrival']) >= previous, 'Destination dates overlap.')
        previous = datetime.date.fromisoformat(stop['arrival']) + datetime.timedelta(days=stop['nights'])
        stops[stop['id']] = stop
    for event in d['events']:
        require(event.get('stopID') in stops and isinstance(event.get('day'), int) and 0 <= event['day'] <= stops[event['stopID']]['nights'], 'Invalid event day or destination.')
        require(isinstance(event.get('minute'), int) and 0 <= event['minute'] < 1440, 'Invalid event time.')
        require(valid_id(event.get('seriesID')), 'Invalid recurring-event identifier.')
        kind = event.get('kind') or 'place'
        require(isinstance(kind, str) and kind in EVENT_KINDS, 'Invalid event type.')
        if kind != 'place':
            text(event.get('title'), 'event title', 500)
        elif event.get('title') is not None:
            text(event['title'], 'event title', 500, True)
        require(event.get('allDay') is None or isinstance(event['allDay'], bool), 'Invalid all-day setting.')
        duration = event.get('durationMinutes')
        require(duration is None or (type(duration) is int and 1 <= duration <= 1440), 'Invalid event duration.')
        if event.get('attendees') is not None:
            text(event['attendees'], 'event guests', 2000, True)
        validate_place(event.get('place'), allow_empty_name=kind != 'place')
        validate_money(event.get('cost'))
        text(event.get('description',''), 'event description', 20000, True)
        require(isinstance(event.get('links'), list) and len(event['links']) <= 30 and all(safe_url(link) for link in event['links']), 'Invalid event links.')
    for hotel in d['hotels']:
        validate_place(hotel.get('place')); validate_money(hotel.get('cost'))
        require(valid_day(hotel.get('checkIn')) and valid_day(hotel.get('checkOut')) and hotel['checkOut'] > hotel['checkIn'], 'Invalid hotel dates.')
        require(isinstance(hotel.get('guests'), int) and 1 <= hotel['guests'] <= 99 and isinstance(hotel.get('rooms'), int) and 1 <= hotel['rooms'] <= 50, 'Invalid hotel guests or rooms.')
        for key in ('roomType','confirmation','notes','overview'):
            text(hotel.get(key,''), key, 20000, True)
    for flight in d['flights']:
        for key in ('airline','departureAirport','arrivalAirport'):
            text(flight.get(key), key, 300)
        for key in ('departureDay','arrivalDay'):
            require(valid_day(flight.get(key)), 'Invalid flight date.')
        for key in ('departureTime','arrivalTime'):
            require(isinstance(flight.get(key), str) and re.fullmatch(r'(?:[01]?\d|2[0-3]):[0-5]\d', flight[key]), 'Invalid flight time.')
        require(not flight.get('bookingLink') or safe_url(flight['bookingLink']), 'Invalid booking link.')
        validate_money(flight.get('cost'))
    total_photos = 0
    for place in d['places']:
        validate_place(place.get('place'))
        require(finite(place.get('overall')) and 0 <= place['overall'] <= 10, 'Invalid personal score.')
        require(isinstance(place.get('scores'), dict) and len(place['scores']) <= 20 and all(isinstance(k, str) and len(k) <= 100 and finite(v) and 0 <= v <= 10 for k,v in place['scores'].items()), 'Invalid category scores.')
        require(place.get('visitedOn') is None or valid_day(place['visitedOn']), 'Invalid visit date.')
        require(place.get('michelinStars') is None or type(place['michelinStars']) is int and 0 <= place['michelinStars'] <= 3, 'Invalid Michelin star record.')
        text(place.get('notes',''), 'visit notes', 20000, True)
        require(isinstance(place.get('photos'), list) and len(place['photos']) <= 6, 'Use up to six photos per place.')
        for photo in place['photos']:
            require(isinstance(photo, dict) and valid_id(photo.get('id')), 'Invalid photo.')
            try:
                raw = base64.b64decode(photo.get('jpeg',''), validate=True)
            except (ValueError, TypeError):
                raise APIError(400, 'Invalid photo encoding.') from None
            require(len(raw) <= 1_500_000 and raw.startswith(b'\xff\xd8\xff'), 'Photos must be JPEG, below 1.5 MB each.')
            total_photos += len(raw)
    require(total_photos <= 28_000_000, 'This shared journey exceeds the 28 MB photo limit.')

def safe_url(value):
    if not isinstance(value, str) or len(value) > 5000:
        return False
    try:
        url = urllib.parse.urlparse(value)
        return url.scheme in ('https','http') and bool(url.hostname) and not url.username and not url.password
    except ValueError:
        return False

def shared_body(body):
    result = copy.deepcopy(body)
    for hotel in result.get('hotels', []):
        hotel['confirmation'] = ''
        hotel['notes'] = ''
    for flight in result.get('flights', []):
        flight['notes'] = ''
    return result

class AurumAPI:
    def __init__(self, database=None):
        self.database = str(database or os.getenv('AURUM_DATABASE', ROOT / 'data/aurum.sqlite3'))
        Path(self.database).parent.mkdir(parents=True, exist_ok=True)
        self.limits = {}
        self.rate_lock = threading.Lock()
        with closing(self.connect()) as db, db:
            db.executescript(SCHEMA)
        try:
            os.chmod(self.database, 0o600)
        except OSError:
            pass
    def connect(self):
        db = sqlite3.connect(self.database, timeout=15)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA foreign_keys=ON')
        db.execute('PRAGMA journal_mode=WAL')
        return db
    def rate_limit(self, key, maximum=180, seconds=60):
        now = time.time()
        with self.rate_lock:
            if len(self.limits) > 10000:
                self.limits = {k:v for k,v in self.limits.items() if v[1] > now}
            count, until = self.limits.get(key, (0, now + seconds))
            if until <= now:
                count, until = 0, now + seconds
            require(count < maximum, 'Too many requests. Please try again later.', 429)
            self.limits[key] = (count + 1, until)
    def __call__(self, environ, start_response):
        status, headers = 200, [('Content-Type','application/json; charset=utf-8')]
        try:
            path = environ.get('PATH_INFO','/')
            method = environ.get('REQUEST_METHOD','GET')
            self.rate_limit(environ.get('REMOTE_ADDR','unknown'))
            if path.startswith('/s/') and method == 'GET':
                payload = self.shared_page(path[3:]).encode()
                headers = [('Content-Type','text/html; charset=utf-8')]
            else:
                size = int(environ.get('CONTENT_LENGTH') or 0)
                require(0 <= size <= 40_000_000, 'Request exceeds 40 MB.', 413)
                body = {}
                if size:
                    require(environ.get('CONTENT_TYPE','').split(';')[0] == 'application/json', 'Send application/json.', 415)
                    body = json.loads(environ['wsgi.input'].read(size), parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
                    require(isinstance(body, dict), 'JSON body must be an object.')
                query = {k:v[0] for k,v in urllib.parse.parse_qs(environ.get('QUERY_STRING','')).items()}
                with closing(self.connect()) as db, db:
                    payload = json.dumps(self.dispatch(db, environ, method, path, query, body), ensure_ascii=False, allow_nan=False).encode()
        except (APIError, providers.ProviderError) as exc:
            status = exc.status
            payload = json.dumps({'error': str(exc)}).encode()
        except (ValueError, TypeError, KeyError, OverflowError):
            status = 400
            payload = b'{"error":"Malformed request. Check the submitted fields."}'
        except Exception:
            status = 500
            payload = b'{"error":"The server could not complete this request. Please try again."}'
        headers += [('Content-Length',str(len(payload))),('Cache-Control','no-store'),('X-Content-Type-Options','nosniff'),('Referrer-Policy','no-referrer'),('X-Frame-Options','DENY'),('Content-Security-Policy',"default-src 'none'; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")]
        phrases = {200:'OK',400:'Bad Request',401:'Unauthorized',403:'Forbidden',404:'Not Found',409:'Conflict',413:'Payload Too Large',415:'Unsupported Media Type',429:'Too Many Requests',500:'Internal Server Error',502:'Bad Gateway',503:'Service Unavailable'}
        start_response(f'{status} {phrases.get(status,"Error")}', headers)
        return [payload]
    def user(self, row):
        return {k:row[k] for k in ('id','handle','name')}
    def account(self, db, env):
        auth = env.get('HTTP_AUTHORIZATION','')
        require(auth.startswith('Bearer '), 'Sign in to your travel account first.', 401)
        hashed = hashlib.sha256(auth[7:].encode()).hexdigest()
        row = db.execute('SELECT users.* FROM users JOIN sessions ON users.id=sessions.user_id WHERE token_hash=? AND expires>?',(hashed,time.time())).fetchone()
        require(row is not None, 'Your session expired. Please sign in again.', 401)
        return row
    def are_friends(self, db, a, b):
        a,b = sorted((a,b))
        return db.execute("SELECT 1 FROM friendships WHERE a=? AND b=? AND status='accepted'",(a,b)).fetchone() is not None
    def get_document(self, db, identifier, user_id, owner=False):
        row = db.execute('SELECT * FROM documents WHERE id=?',(identifier,)).fetchone()
        require(row is not None, 'Journey not found.', 404)
        if row['owner_id'] == user_id:
            return row
        require(not owner and self.can_read(db,row,user_id), 'You don’t have access to this journey.', 403)
        return row
    def can_read(self, db, row, user_id):
        return row['owner_id'] == user_id or row['visibility'] == 'public' or (row['visibility'] == 'friends' and self.are_friends(db,row['owner_id'],user_id)) or db.execute('SELECT 1 FROM grants WHERE document_id=? AND user_id=?',(row['id'],user_id)).fetchone() is not None
    def remote_document(self, db, row, viewer):
        body = json.loads(row['body'])
        return {'id':row['id'],'owner':self.user(db.execute('SELECT * FROM users WHERE id=?',(row['owner_id'],)).fetchone()),'document':body if row['owner_id'] == viewer else shared_body(body),'revision':row['revision']}
    def conversation(self, db, identifier, user_id):
        require(db.execute('SELECT 1 FROM members WHERE conversation_id=? AND user_id=?',(identifier,user_id)).fetchone(), 'You aren’t a member of this conversation.',403)
        row = db.execute('SELECT * FROM conversations WHERE id=?',(identifier,)).fetchone()
        return {'id':row['id'],'name':row['name'],'members':[self.user(r) for r in db.execute('SELECT users.* FROM users JOIN members ON users.id=members.user_id WHERE conversation_id=? ORDER BY users.name',(identifier,))]}
    def message(self, db, row):
        return {'id':row['id'],'sender':self.user(db.execute('SELECT * FROM users WHERE id=?',(row['sender_id'],)).fetchone()),'text':row['text'],'documentID':row['document_id'],'createdAt':row['created']}
    def dispatch(self, db, env, method, path, q, body):
        if path == '/v1/status' and method == 'GET':
            public = os.getenv('PUBLIC_BASE_URL','')
            return {'flightTracking':flight_provider.connected(),'flightHistory':flight_provider.history_enabled(),'googlePlaces':bool(os.getenv('GOOGLE_PLACES_API_KEY')),'tripadvisor':bool(os.getenv('TRIPADVISOR_API_KEY')),'ai':bool(os.getenv('OPENAI_API_KEY')),'publicSharing':safe_url(public) and public.startswith('https://')}
        if path in ('/v1/flights/status', '/v1/flights/history', '/v1/flights/position') and method == 'GET':
            peer = env.get('REMOTE_ADDR', '')
            local_dev = peer in ('127.0.0.1', '::1') and os.getenv('HOST', '127.0.0.1') in ('127.0.0.1', '::1', 'localhost') and not os.getenv('PUBLIC_BASE_URL')
            identity = peer if local_dev else self.account(db, env)['id']
            self.rate_limit('flights:' + identity, 20, 60)
            if path.endswith('/position'):
                return flight_provider.position(q.get('id', ''))
            handler = flight_provider.history if path.endswith('/history') else flight_provider.status
            return handler(q.get('q', ''), q.get('date', ''))
        if path == '/v1/locations/autocomplete' and method == 'GET':
            peer = env.get('REMOTE_ADDR', '')
            # Direct loopback development only; never trust forwarding headers for this exception.
            local_dev = peer in ('127.0.0.1', '::1') and os.getenv('HOST', '127.0.0.1') in ('127.0.0.1', '::1', 'localhost') and not os.getenv('PUBLIC_BASE_URL')
            identity = peer if local_dev else self.account(db, env)['id']
            self.rate_limit('autocomplete:' + identity, 60, 60)
            return providers.autocomplete_places(q.get('q', ''))
        if path in ('/v1/auth/register','/v1/auth/login') and method == 'POST':
            self.rate_limit('auth:'+env.get('REMOTE_ADDR','unknown'),20,300)
            handle = str(body.get('handle','')).strip().lower()
            password = body.get('password','')
            require(re.fullmatch(r'[a-z0-9_]{3,32}',handle), 'Use a username with 3–32 letters, numbers or underscores.')
            require(isinstance(password,str) and 12 <= len(password) <= 256, 'Use a password with 12–256 characters.')
            if path.endswith('register'):
                name = body.get('name','').strip() or handle
                text(name,'display name',100)
                require(db.execute('SELECT 1 FROM users WHERE handle=?',(handle,)).fetchone() is None,'That username is already taken.',409)
                salt = secrets.token_bytes(16)
                hashed = hashlib.scrypt(password.encode(),salt=salt,n=16384,r=8,p=1).hex()
                identifier = str(uuid.uuid4())
                db.execute('INSERT INTO users VALUES(?,?,?,?,?)',(identifier,handle,name,salt.hex()+':'+hashed,time.time()))
                row = db.execute('SELECT * FROM users WHERE id=?',(identifier,)).fetchone()
            else:
                row = db.execute('SELECT * FROM users WHERE handle=?',(handle,)).fetchone()
                encoded = row['password'] if row else '00'*16+':'+'00'*64
                salt, expected = encoded.split(':')
                actual = hashlib.scrypt(password.encode(),salt=bytes.fromhex(salt),n=16384,r=8,p=1).hex()
                require(row is not None and hmac.compare_digest(actual,expected),'Username or password is incorrect.',401)
            token = secrets.token_urlsafe(40)
            db.execute('DELETE FROM sessions WHERE expires<?',(time.time(),))
            db.execute('INSERT INTO sessions VALUES(?,?,?)',(hashlib.sha256(token.encode()).hexdigest(),row['id'],time.time()+30*86400))
            return {'token':token,'user':self.user(row)}
        user = self.account(db,env)
        uid = user['id']
        if path == '/v1/me' and method == 'GET':
            return self.user(user)
        if path == '/v1/auth/logout' and method == 'POST':
            db.execute('DELETE FROM sessions WHERE token_hash=?',(hashlib.sha256(env['HTTP_AUTHORIZATION'][7:].encode()).hexdigest(),))
            return {'ok':True}
        if path == '/v1/places/search' and method == 'GET':
            self.rate_limit('provider:'+uid,30,60)
            return providers.search_places(q.get('q',''),q.get('category','attractions'))
        if re.fullmatch(r'/v1/places/\d+',path) and method == 'GET':
            self.rate_limit('provider:'+uid,30,60)
            return providers.place_details(path.rsplit('/',1)[-1])
        if path == '/v1/ai/activities' and method == 'POST':
            self.rate_limit('ai:'+uid,10,3600)
            return providers.recommend(body.get('city',''),body.get('interests',''))
        if path == '/v1/ai/hotel' and method == 'POST':
            self.rate_limit('ai:'+uid,10,3600)
            return providers.hotel_overview(body)
        if path == '/v1/friends':
            if method == 'GET':
                result = []
                for row in db.execute('SELECT * FROM friendships WHERE a=? OR b=?',(uid,uid)):
                    friend = self.user(db.execute('SELECT * FROM users WHERE id=?',(row['b'] if row['a']==uid else row['a'],)).fetchone())
                    result.append({**friend,'status':row['status'],'incoming':row['requester']!=uid})
                return result
            if method == 'POST':
                handle = str(body.get('handle','')).strip().lower()
                other = db.execute('SELECT * FROM users WHERE handle=?',(handle,)).fetchone()
                require(other is not None,'No account has that username.',404)
                require(other['id'] != uid,'Choose another traveler.')
                a,b = sorted((uid,other['id']))
                require(db.execute('SELECT 1 FROM friendships WHERE a=? AND b=?',(a,b)).fetchone() is None,'A friendship or request already exists.',409)
                db.execute("INSERT INTO friendships VALUES(?,?,?,'pending')",(a,b,uid))
                return {'ok':True}
        if path.startswith('/v1/friends/') and method in ('PUT','DELETE'):
            other = path.rsplit('/',1)[-1]; a,b = sorted((uid,other))
            row = db.execute('SELECT * FROM friendships WHERE a=? AND b=?',(a,b)).fetchone()
            require(row is not None,'Friend request not found.',404)
            if method == 'PUT':
                require(row['requester'] != uid and row['status']=='pending','Only the recipient can accept a pending request.',403)
                db.execute("UPDATE friendships SET status='accepted' WHERE a=? AND b=?",(a,b))
            else:
                db.execute('DELETE FROM friendships WHERE a=? AND b=?',(a,b))
                db.execute('DELETE FROM grants WHERE (user_id=? AND document_id IN (SELECT id FROM documents WHERE owner_id=?)) OR (user_id=? AND document_id IN (SELECT id FROM documents WHERE owner_id=?))',(uid,other,other,uid))
            return {'ok':True}
        if path in ('/v1/documents','/v1/feed') and method == 'GET':
            if path.endswith('documents'):
                rows = db.execute('SELECT * FROM documents WHERE owner_id=? ORDER BY updated DESC LIMIT 200',(uid,)).fetchall()
            else:
                rows = [r for r in db.execute("SELECT * FROM documents WHERE owner_id!=? AND visibility IN ('friends','public') ORDER BY updated DESC",(uid,)) if self.are_friends(db,uid,r['owner_id'])][:100]
            return [self.remote_document(db,row,uid) for row in rows]
        match = re.fullmatch(r'/v1/documents/([a-fA-F0-9-]+)(?:/(link|revoke))?',path)
        if match:
            identifier, action = match.groups()
            require(valid_id(identifier),'Invalid document identifier.')
            if method == 'PUT' and not action:
                validate_document(body)
                require(body['id'] == identifier,'Document ID does not match path.')
                existing = db.execute('SELECT * FROM documents WHERE id=?',(identifier,)).fetchone()
                if existing:
                    require(existing['owner_id'] == uid,'Only the owner can edit this journey.',403)
                    # Explicit conflict detection avoids quietly overwriting a newer cloud copy.
                    require(body['updatedAt'] >= json.loads(existing['body']).get('updatedAt',0),'A newer cloud copy exists. Download it before updating.',409)
                    if body['visibility'] == 'private' and existing['visibility'] != 'private':
                        db.execute('DELETE FROM links WHERE document_id=?',(identifier,)); db.execute('DELETE FROM grants WHERE document_id=?',(identifier,))
                    db.execute('UPDATE documents SET body=?,visibility=?,revision=revision+1,updated=? WHERE id=?',(json.dumps(body),body['visibility'],time.time(),identifier))
                else:
                    db.execute('INSERT INTO documents(id,owner_id,body,visibility,updated) VALUES(?,?,?,?,?)',(identifier,uid,json.dumps(body),body['visibility'],time.time()))
                return self.remote_document(db,self.get_document(db,identifier,uid),uid)
            row = self.get_document(db,identifier,uid,owner=method!='GET' or action is not None)
            if method == 'GET' and not action:
                return self.remote_document(db,row,uid)
            if method == 'DELETE' and not action:
                db.execute('DELETE FROM documents WHERE id=?',(identifier,)); return {'ok':True}
            if method == 'POST' and action == 'link':
                base = os.getenv('PUBLIC_BASE_URL','').rstrip('/')
                require(safe_url(base) and base.startswith('https://'),'Deploy this backend to HTTPS and set PUBLIC_BASE_URL to create shareable links.',503)
                token = secrets.token_urlsafe(32)
                db.execute('INSERT INTO links VALUES(?,?,?)',(token,identifier,time.time()))
                return {'url':base+'/s/'+token}
            if method == 'POST' and action == 'revoke':
                db.execute('DELETE FROM links WHERE document_id=?',(identifier,)); db.execute('DELETE FROM grants WHERE document_id=?',(identifier,))
                doc = json.loads(row['body']); doc['visibility'] = 'private'
                db.execute("UPDATE documents SET visibility='private',body=?,revision=revision+1 WHERE id=?",(json.dumps(doc),identifier))
                return {'ok':True}
        if path == '/v1/conversations':
            if method == 'GET':
                return [self.conversation(db,row['id'],uid) for row in db.execute('SELECT conversations.* FROM conversations JOIN members ON conversations.id=members.conversation_id WHERE user_id=? ORDER BY created DESC',(uid,))]
            if method == 'POST':
                name = body.get('name',''); text(name,'conversation name',100)
                members = body.get('members')
                require(isinstance(members,list) and 1 <= len(members) <= 30 and all(isinstance(member,str) for member in members),'Choose 1–30 friends.')
                require(all(member != uid and self.are_friends(db,uid,member) for member in members),'All invited members must be accepted friends.',403)
                # Reuse a direct conversation, rather than duplicating it for each share.
                if len(set(members)) == 1:
                    for row in db.execute('SELECT conversation_id FROM members WHERE user_id=?',(uid,)):
                        existing = {r['user_id'] for r in db.execute('SELECT user_id FROM members WHERE conversation_id=?',(row['conversation_id'],))}
                        if existing == {uid,members[0]}:
                            return self.conversation(db,row['conversation_id'],uid)
                identifier = str(uuid.uuid4())
                db.execute('INSERT INTO conversations VALUES(?,?,?,?)',(identifier,name,uid,time.time()))
                for member in set(members+[uid]):
                    db.execute('INSERT INTO members VALUES(?,?)',(identifier,member))
                return self.conversation(db,identifier,uid)
        match = re.fullmatch(r'/v1/conversations/([a-fA-F0-9-]+)/messages',path)
        if match:
            identifier = match.group(1); conversation = self.conversation(db,identifier,uid)
            if method == 'GET':
                rows = db.execute('SELECT * FROM messages WHERE conversation_id=? ORDER BY created DESC LIMIT 300',(identifier,)).fetchall()
                return [self.message(db,row) for row in reversed(rows)]
            if method == 'POST':
                content = body.get('text',''); doc_id = body.get('documentID')
                text(content,'message',5000,True); require(content.strip() or doc_id,'Add a message or journey.')
                if doc_id:
                    self.get_document(db,doc_id,uid,owner=True)
                    for member in conversation['members']:
                        if member['id'] != uid:
                            # A removed friend cannot regain document access from an old group.
                            require(self.are_friends(db,uid,member['id']),'Every recipient must still be your friend to share a journey.',403)
                            db.execute('INSERT OR IGNORE INTO grants VALUES(?,?)',(doc_id,member['id']))
                message_id = str(uuid.uuid4())
                db.execute('INSERT INTO messages VALUES(?,?,?,?,?,?)',(message_id,identifier,uid,content,doc_id,time.time()))
                return self.message(db,db.execute('SELECT * FROM messages WHERE id=?',(message_id,)).fetchone())
        raise APIError(404,'Endpoint not found.')
    def shared_page(self, token):
        require(re.fullmatch(r'[A-Za-z0-9_-]{30,80}',token),'This link is unavailable.',404)
        with closing(self.connect()) as db, db:
            row = db.execute('SELECT documents.*, users.name AS owner_name FROM links JOIN documents ON links.document_id=documents.id JOIN users ON documents.owner_id=users.id WHERE links.token=?',(token,)).fetchone()
            require(row is not None,'This link was revoked or is no longer available.',404)
            return render_shared(shared_body(json.loads(row['body'])),row['owner_name'])

def render_shared(d, owner):
    esc = lambda v: html.escape(str(v or ''), quote=True)
    def link(url, label):
        return f'<a href="{esc(url)}" rel="noreferrer noopener" target="_blank">{esc(label)} ↗</a>' if safe_url(url) else ''
    def money(cost):
        return f"{esc(cost['currency'])} {esc(format(cost['amount'], ',.2f'))}" if cost else ''
    def place_details(p):
        content = f'<p class="muted">{esc(p.get("address"))}</p><div class="actions">'
        if p.get('latitude') is not None:
            url = 'https://maps.apple.com/?'+urllib.parse.urlencode({'q':p['name'],'ll':f"{p['latitude']},{p['longitude']}"})
            content += link(url,'Open in Maps')
        content += link(p.get('website'),'Website') + link(p.get('sourceURL'),p.get('source','Source')) + '</div>'
        return content
    pieces = []
    if d['stops'] or d['events'] or d['hotels'] or d['flights']:
        for stop in d['stops']:
            pieces.append(f'<section><div class="eyebrow">YOUR ROUTE · {stop["nights"]} NIGHTS</div><h2>{esc(stop["name"])}</h2>')
            for day in range(stop['nights']+1):
                events = sorted((e for e in d['events'] if e['stopID']==stop['id'] and e['day']==day),key=lambda e:-1 if e.get('allDay') else e['minute'])
                label = (datetime.date.fromisoformat(stop['arrival'])+datetime.timedelta(days=day)).strftime('%a, %b %d') if d['dateMode']=='dates' else f'Day {day+1}'
                pieces.append(f'<h3>{esc(label)}</h3>')
                if not events:
                    pieces.append('<p class="muted">A little room for discovery.</p>')
                for event in events:
                    p = event['place']
                    kind = event.get('kind') or 'place'
                    title = p['name'] if kind == 'place' else event['title']
                    category = p['category'] if kind == 'place' else EVENT_KINDS[kind]
                    clock = 'All day' if event.get('allDay') else f"{event['minute']//60:02}:{event['minute']%60:02}"
                    if not event.get('allDay') and event.get('durationMinutes'):
                        end = event['minute'] + event['durationMinutes']
                        clock += f" – {(end//60)%24:02}:{end%60:02}" + (' (+1 day)' if end >= 1440 else '')
                    venue = f'<p>{esc(p["name"])}</p>' if kind != 'place' and p['name'] else ''
                    guests = f'<p>{esc(event["attendees"])}</p>' if event.get('attendees') else ''
                    pieces.append(f'<article><div class="eyebrow">{clock} · {esc(category)}</div><h3>{esc(title)}</h3>{venue}{guests}<p>{esc(event.get("description"))}</p>{place_details(p)}<p class="price">{money(event.get("cost"))}</p><div class="actions">'+''.join(link(url,'Details') for url in event.get('links',[]))+'</div></article>')
            pieces.append('</section>')
        if d['hotels'] or d['flights']:
            pieces.append('<section><div class="eyebrow">THE STAY & THE JOURNEY</div><h2>All the pieces, together.</h2>')
            for h in d['hotels']:
                pieces.append(f'<article><h3>{esc(h["place"]["name"])}</h3><p>{esc(h["checkIn"])} — {esc(h["checkOut"])} · {h["guests"]} guests · {h["rooms"]} rooms</p><p>{esc(h.get("roomType"))}</p>{place_details(h["place"])}<p class="price">{money(h.get("cost"))}</p></article>')
            for f in d['flights']:
                pieces.append(f'<article><h3>{esc(f["departureAirport"])} → {esc(f["arrivalAirport"])}</h3><p>{esc(f["airline"])} {esc(f.get("flightNumber"))}</p><p>{esc(f["departureDay"])} {esc(f["departureTime"])} {esc(f.get("departureZone"))}<br>{esc(f["arrivalDay"])} {esc(f["arrivalTime"])} {esc(f.get("arrivalZone"))}</p><p class="muted">Airport-local times</p><p class="price">{money(f.get("cost"))}</p>{link(f.get("bookingLink"),"Flight details")}</article>')
            pieces.append('</section>')
        from decimal import Decimal
        totals = {}
        for item in d['events']+d['hotels']+d['flights']:
            cost = item.get('cost')
            if cost:
                totals[cost['currency']] = totals.get(cost['currency'],Decimal(0))+Decimal(str(cost['amount']))
        pieces.append('<section><h2>The planned cost</h2>'+''.join(f'<p class="price">{esc(currency)} {value:,.2f}</p>' for currency,value in sorted(totals.items()))+'<p class="muted">Currencies stay separate. Unpriced items are excluded. Plans and booking records do not confirm a reservation.</p></section>')
    if d['places']:
        pieces.append('<section><div class="eyebrow">TRIP JOURNAL</div><h2>The places that stayed with you.</h2></section>')
        for place in d['places']:
            p = place['place']
            score = f'{place["overall"]:.1f}<small>/10</small>' if place['overall'] else 'To rate'
            pieces.append(f'<article class="visited"><div class="topline"><span class="eyebrow">{esc(p["category"])}</span><span class="score">{score}</span></div><h2>{esc(p["name"])}</h2><p class="muted">{esc(place.get("visitedOn") or "Visit date not recorded")} · {esc(place.get("priceRange"))}</p><p>{esc(place.get("notes"))}</p>{place_details(p)}<div class="scores">')
            pieces.extend(f'<span>{esc(category)} <b>{value:.1f}</b></span>' for category,value in place['scores'].items() if value)
            pieces.append('</div>')
            if place.get('michelinStars') is not None:
                pieces.append(f'<p class="muted">Michelin stars recorded by traveler: {place["michelinStars"]}. Not a verified current award.</p>')
            if place['photos']:
                pieces.append('<div class="photos">'+''.join(f'<img alt="Traveler photograph of {esc(p["name"])}" loading="lazy" src="data:image/jpeg;base64,{photo["jpeg"]}">' for photo in place['photos'])+'</div>')
            pieces.append('</article>')
    score_values = [p['overall'] for p in d['places'] if p['overall'] > 0]
    stats = f'{len(d["stops"])} destinations · {len(d["events"])} plans · {len(d["places"])} journal places'+(f' · {sum(score_values)/len(score_values):.1f} average personal score' if score_values else '')
    route = ' → '.join(s['name'] for s in d['stops']) or d.get('destination','')
    return '''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>'''+esc(d['title'])+''' · Aurum</title><style>
:root{color-scheme:light dark;--canvas:#f7f5ef;--card:#fffefa;--ink:#202822;--muted:#717871;--gold:#926e44;--line:#deded4}*{box-sizing:border-box}body{margin:0;background:var(--canvas);color:var(--ink);font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif;line-height:1.6}header{background:linear-gradient(135deg,#17342e,#486454);color:#fffdf5;padding:42px max(24px,calc((100% - 820px)/2)) 70px}.brand{letter-spacing:.3em;font-size:14px}.badge{display:inline-block;border:1px solid #ffffff40;background:#ffffff12;border-radius:30px;padding:7px 13px;font-size:11px;margin:25px 0 12px}h1,h2,h3{font-family:Georgia,"Times New Roman",serif;font-weight:400;line-height:1.15;letter-spacing:-.04em}h1{font-size:clamp(38px,7vw,68px);margin:12px 0 22px;overflow-wrap:anywhere}h2{font-size:31px;margin:14px 0}h3{font-size:23px;margin:12px 0}header p{opacity:.8}.wrap{max-width:868px;margin:-26px auto 0;padding:0 24px 50px}.summary,article,section{background:var(--card);border:1px solid var(--line);border-radius:26px;padding:27px;margin-bottom:20px;overflow:hidden}section article{background:var(--canvas);border:0;padding:22px}.summary{position:relative;margin-bottom:35px}.eyebrow{text-transform:uppercase;color:var(--gold);font-size:10px;letter-spacing:.16em;font-weight:600}.muted{color:var(--muted);font-size:14px}.price{font-size:19px;color:var(--gold);font-variant-numeric:tabular-nums}.actions{display:flex;gap:10px;flex-wrap:wrap}a{display:inline-block;text-decoration:none;color:var(--gold);border:1px solid var(--line);border-radius:30px;padding:9px 15px;font-size:13px}p{white-space:pre-wrap;overflow-wrap:anywhere}.topline{display:flex;align-items:center;justify-content:space-between}.score{color:var(--gold);font-size:29px}.score small{font-size:13px;color:var(--muted)}.scores{display:flex;flex-wrap:wrap;gap:8px;margin-top:20px}.scores span{background:var(--canvas);padding:9px 14px;border-radius:20px;font-size:12px}.scores b{margin-left:8px}.photos{display:flex;overflow:auto;gap:12px;margin-top:24px}.photos img{height:230px;max-width:90%;object-fit:cover;border-radius:18px}footer{text-align:center;color:var(--muted);font-size:12px;padding:30px}@media(prefers-color-scheme:dark){:root{--canvas:#151b17;--card:#202822;--ink:#f5f3ec;--muted:#a9b3a8;--gold:#d2b58c;--line:#354237}}@media(max-width:500px){.wrap{padding-left:14px;padding-right:14px}section,article,.summary{padding:21px;border-radius:23px}}
</style></head><body><header><div class="brand">AURUM</div><div class="badge">A read-only shared journey</div><h1>'''+esc(d['title'])+'''</h1><p>'''+esc(route)+'''</p></header><main class="wrap"><div class="summary"><div class="eyebrow">Through '''+esc(owner)+'''’s eyes</div><p>'''+esc(d.get('description'))+'''</p><p class="muted">'''+esc(stats)+'''</p></div>'''+''.join(pieces)+'''</main><footer>AURUM · Made for the journey.<br>This is a read-only shared view. Private booking references are hidden.</footer></body></html>'''

app = AurumAPI()

class QuietHandler(WSGIRequestHandler):
    def log_message(self, format, *args):
        # Capability tokens in /s URLs and credentials must not appear in access logs.
        pass
class ThreadedServer(ThreadingMixIn, WSGIServer):
    daemon_threads = True

if __name__ == '__main__':
    host = os.getenv('HOST','127.0.0.1')
    port = int(os.getenv('PORT','8787'))
    print(f'Aurum backend listening on {host}:{port}',flush=True)
    with make_server(host,port,app,server_class=ThreadedServer,handler_class=QuietHandler) as server:
        server.serve_forever()
