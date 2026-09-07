"""Live contract/security checks. Creates temporary users and deletes them in finally.
No emails, real bookings, payments or messages to existing users are sent.
Run with SEUR_TEST_URL optionally set. Use --providers for two bounded live lookups.
"""
import base64,copy,json,os,secrets,sys,time,urllib.request,urllib.error,uuid
from pathlib import Path
BASE=os.getenv('SEUR_TEST_URL','https://bwrodcxmdzrpyrshrlfd.supabase.co/functions/v1/travel-api')
PUB='sb_publishable_akTFJhbVImY79drnvbMwog_-DFtfJFz'
ROOT=BASE.split('/functions/')[0]
def call(method,path,body=None,token=None,expected=200,raw=False,_retry=False):
 req=urllib.request.Request(path if path.startswith('https://') else BASE+path,data=json.dumps(body).encode() if body is not None else None,method=method,headers={'Content-Type':'application/json',**({'Authorization':'Bearer '+token} if token else {})})
 try:
  with urllib.request.urlopen(req,timeout=50) as r:code,data=r.status,r.read()
 except urllib.error.HTTPError as e:code,data=e.code,e.read()
 except (TimeoutError,urllib.error.URLError):
  if method=='GET' and not _retry:return call(method,path,body,token,expected,raw,True)
  raise
 if code!=expected:raise AssertionError(f'{method} {path.split("?")[0]} expected {expected}, got {code}: {data[:350]!r}')
 return data if raw else json.loads(data)
def check_denied(path,jwt=None,body=None):
 req=urllib.request.Request(ROOT+'/rest/v1/'+path,headers={'apikey':PUB,'Content-Type':'application/json',**({'Authorization':'Bearer '+jwt} if jwt else {})},data=json.dumps(body).encode() if body is not None else None)
 try:
  with urllib.request.urlopen(req,timeout=20) as r:data=r.read();code=r.status
 except urllib.error.HTTPError as e:code=e.code;data=e.read()
 assert code in (401,403,404),('Unexpected public database access',path,code,data[:100])
def make_document():
 stop=str(uuid.uuid4()).upper();p={'id':'fixture','name':'A memorable table','category':'restaurant','city':'Paris','address':'12 Example Street','phone':'','website':'https://example.com','source':'Test fixture','overview':'','latitude':48.85,'longitude':2.35}
 photo=base64.b64encode(Path('iOS/Aurum/Assets.xcassets/paris.imageset/paris.jpg').read_bytes()).decode()
 return {'id':str(uuid.uuid4()).upper(),'kind':'journey','title':'Supabase integration test','destination':'Paris','description':'Temporary automated test','dateMode':'dates','startDate':'2026-10-01','endDate':'2026-10-04','visibility':'private','stops':[{'id':stop,'name':'Paris','code':'PAR','country':'France','arrival':'2026-10-01','nights':3}], 'events':[{'id':str(uuid.uuid4()),'seriesID':str(uuid.uuid4()),'stopID':stop,'day':0,'minute':1410,'kind':'meeting','title':'Evening review','durationMinutes':90,'attendees':'Test guests','place':p,'description':'Meeting','links':['https://example.com'],'cost':{'amount':85.5,'currency':'EUR'}}], 'hotels':[{'id':str(uuid.uuid4()),'place':{**p,'id':'hotel','category':'hotel'},'checkIn':'2026-10-01','checkOut':'2026-10-04','guests':2,'rooms':1,'roomType':'Suite','confirmation':'PRIVATE-CONFIRMATION','notes':'PRIVATE-NOTE','overview':'','cost':{'amount':600,'currency':'EUR'}}], 'flights':[{'id':str(uuid.uuid4()),'airline':'British Airways','flightNumber':'BA178','departureAirport':'JFK','arrivalAirport':'LHR','departureDay':'2026-10-01','arrivalDay':'2026-10-02','departureTime':'21:00','arrivalTime':'09:00','notes':'PRIVATE-FLIGHT-NOTE','bookingLink':'https://example.com'}], 'places':[{'id':str(uuid.uuid4()),'place':p,'overall':9.4,'scores':{'Food':9.6},'notes':'A lovely evening','priceRange':'$$$$','visitedOn':'2026-10-02','michelinStars':1,'photos':[{'id':str(uuid.uuid4()),'jpeg':photo}]}],'updatedAt':time.time()}
users=[]
try:
 status=call('GET','/v1/status');assert status['backend']=='supabase' and status['publicSharing']
 for endpoint in ['/v1/me','/v1/documents','/v1/friends','/v1/flights/status?q=BA178&date=2026-09-07','/v1/locations/autocomplete?q=Savoy']:
  call('GET',endpoint,expected=401)
 check_denied('travel_documents?select=*');check_denied('rpc/travel_dispatch',body={'actor':str(uuid.uuid4()),'method':'GET','path':'/v1/documents'})
 password=secrets.token_urlsafe(24)
 for label in ['alice','bob','carol']:
  user=call('POST','/v1/auth/register',{'handle':'migration_'+label+'_'+secrets.token_hex(3),'name':'Temporary '+label,'password':password});users.append(user)
 a,b,c=users;aid,bid,cid=[v['user']['id'] for v in users];at,bt,ct=[v['token'] for v in users]
 assert call('GET','/v1/me',token=at)['id']==aid
 call('POST','/v1/auth/login',{'handle':a['user']['handle'],'password':'wrong-password-long'},expected=401)
 # Verify native Supabase authenticated roles cannot bypass the Edge access checks.
 req=urllib.request.Request(ROOT+'/auth/v1/token?grant_type=password',headers={'apikey':PUB,'Content-Type':'application/json'},data=json.dumps({'email':a['user']['handle']+'@accounts.seur.invalid','password':password}).encode())
 with urllib.request.urlopen(req,timeout=20) as r:jwt=json.load(r)['access_token']
 check_denied('travel_documents?select=*',jwt);check_denied('travel_sessions?select=*',jwt)
 d=make_document();path='/v1/documents/'+d['id'];saved=call('PUT',path,d,at);assert saved['revision']==1
 restored=call('GET',path,token=at)['document'];assert restored==d,'Document/photo roundtrip changed data'
 listing=call('GET','/v1/documents',token=at);assert listing[0]['isSummary'] and listing[0]['document']['places'][0]['photos']==[]
 call('GET',path,token=bt,expected=403);call('PUT',path,d,bt,expected=403)
 bad=copy.deepcopy(d);bad['events'][0]['minute']=1440;call('PUT',path,bad,at,expected=400)
 bad=copy.deepcopy(d);bad['places'][0]['photos'][0]['jpeg']=base64.b64encode(b'not JPEG').decode();call('PUT',path,bad,at,expected=400)
 old=copy.deepcopy(d);d['updatedAt']+=1;assert call('PUT',path,d,at)['revision']==2;call('PUT',path,old,at,expected=409)
 call('POST','/v1/friends',{'handle':b['user']['handle']},at)
 call('PUT','/v1/friends/'+bid,{},at,expected=403)
 call('PUT','/v1/friends/'+aid,{},bt)
 d['visibility']='friends';d['updatedAt']+=1;call('PUT',path,d,at)
 shared=call('GET',path,token=bt)['document'];assert shared['hotels'][0]['confirmation']=='' and shared['hotels'][0]['notes']=='' and shared['flights'][0]['notes']==''
 assert shared['places'][0]['photos']==d['places'][0]['photos']
 assert len(call('GET','/v1/feed',token=bt))==1
 group=call('POST','/v1/conversations',{'name':'Temporary test chat','members':[bid]},at)
 assert call('POST','/v1/conversations',{'name':'Same participants','members':[bid]},at)['id']==group['id']
 call('POST','/v1/conversations',{'name':'Forbidden','members':[cid]},at,expected=403)
 chat='/v1/conversations/'+group['id']+'/messages'
 call('GET',chat,token=ct,expected=403);call('POST',chat,{'text':'Temporary test share','documentID':d['id']},at)
 assert len(call('GET',chat,token=bt))==1
 link=call('POST',path+'/link',{},at)['url'];doc=call('GET',link+'?format=json')['document'];assert doc['hotels'][0]['confirmation']==''
 pdf=call('GET',link,raw=True);assert pdf.startswith(b'%PDF');Path('/tmp/seur-shared-trip.pdf').write_bytes(pdf)
 txt=call('GET',link+'?format=txt',raw=True).decode();assert 'Evening review' in txt and 'PRIVATE-' not in txt
 call('DELETE','/v1/friends/'+bid,{},at);call('GET',path,token=bt,expected=403)
 call('POST',chat,{'text':'Cannot restore grant','documentID':d['id']},at,expected=403)
 call('POST',path+'/revoke',{},at);call('GET',link,expected=404)
 d['visibility']='public';d['updatedAt']+=1;call('PUT',path,d,at);assert call('GET',path,token=ct)['document']['title']==d['title']
 d['visibility']='private';d['updatedAt']+=1;call('PUT',path,d,at);call('GET',path,token=ct,expected=403)
 if '--providers' in sys.argv:
  from datetime import datetime,timezone
  feed=call('GET','/v1/flights/status?q=BA178&date='+datetime.now(timezone.utc).date().isoformat(),token=at);print('Live FlightAware returned',len(feed['flights']),'matching departures')
  suggestions=call('GET','/v1/locations/autocomplete?q=The%20Savoy%20London',token=at);assert suggestions;print('Live Google Places returned',len(suggestions),'suggestions')
 call('GET','/v1/flights/history?q=BA178&date=2026-09-07',token=at,expected=503)
 call('DELETE',path,{},at);call('GET',path,token=at,expected=404)
 extra=call('POST','/v1/auth/login',{'handle':a['user']['handle'],'password':password})
 call('POST','/v1/auth/logout',{},extra['token']);call('GET','/v1/me',token=extra['token'],expected=401)
 print('PASS: live authentication, authorization, photo roundtrip, plans/journal, conflicts, friends, groups, sharing, PDFs, revocation and logout')
finally:
 for u in reversed(users):
  try:call('DELETE','/v1/account',{},u['token']);print('Removed temporary test account')
  except Exception as e:print('CLEANUP FAILED:',str(e));raise
