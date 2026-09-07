"""Verify standalone flight ownership and bounded live searches with disposable accounts."""
import json,secrets,urllib.request,urllib.error,uuid,datetime,sys
BASE='https://bwrodcxmdzrpyrshrlfd.supabase.co/functions/v1/travel-api'
def call(method,path,token=None,body=None,expected=200,retry=True):
    req=urllib.request.Request(BASE+path,method=method,headers={'Content-Type':'application/json',**({'Authorization':'Bearer '+token} if token else {})},data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req,timeout=50) as r: code,data=r.status,r.read()
    except urllib.error.HTTPError as e: code,data=e.code,e.read()
    except (TimeoutError,urllib.error.URLError):
        if retry and method in ("GET","PUT","DELETE"): return call(method,path,token,body,expected,False)
        raise
    assert code==expected,(path,code,data[:250])
    return json.loads(data)
users=[]
try:
    call('GET','/v1/my-flights',expected=401)
    for label in ['a','b']:
        users.append(call('POST','/v1/auth/register',body={'handle':'flightqa_'+label+'_'+secrets.token_hex(4),'name':'Flight QA','password':secrets.token_urlsafe(24)}))
    a,b=[u['token'] for u in users]
    f={'id':str(uuid.uuid4()),'airline':'British Airways','flightNumber':'BA178','departureAirport':'JFK','arrivalAirport':'LHR','departureDay':'2026-09-07','arrivalDay':'2026-09-08','departureTime':'18:00','arrivalTime':'06:00','departureLatitude':40.6413,'departureLongitude':-73.7781,'arrivalLatitude':51.47,'arrivalLongitude':-.4543,'departureZone':'America/New_York','arrivalZone':'Europe/London','notes':'Private QA flight','bookingLink':''}
    path='/v1/my-flights/'+f['id']
    assert call('PUT',path,a,f)==f
    assert call('GET','/v1/my-flights',a)==[f]
    assert call('GET','/v1/my-flights',b)==[]
    call('DELETE',path,b)
    assert call('GET','/v1/my-flights',a)==[f]
    call('PUT',path,a,{**f,'departureLatitude':100},expected=400)
    f['notes']='Updated';call('PUT',path,a,f);assert call('GET','/v1/my-flights',a)[0]['notes']=='Updated'
    if '--providers' in sys.argv:
        today=datetime.datetime.now(datetime.timezone.utc).date().isoformat()
        feed=call('GET','/v1/flights/status?q=BA178&date='+today,a);assert 'flights' in feed
        route=call('GET','/v1/flights/route?origin=JFK&destination=LHR&date='+today,a);assert 'flights' in route
        airport=call('GET','/v1/flights/airport?code=JFK',a);assert airport['code']=='JFK' and abs(airport['latitude']-40.6)<1
        nearby=call('GET','/v1/flights/airport-nearby?latitude=40.6413&longitude=-73.7781',a);assert nearby['code']=='JFK'
        print('Live number search:',len(feed['flights']),'results; route search:',len(route['flights']),'results; JFK airport and autocomplete resolution verified.')
    call('DELETE',path,a);assert call('GET','/v1/my-flights',a)==[]
    print('Standalone flight create, reload, edit, delete, authentication and cross-account isolation passed.')
finally:
    for u in users:call('DELETE','/v1/account',u['token'])
    print('Temporary accounts removed.')
