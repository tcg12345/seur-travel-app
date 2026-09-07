import copy
import io
import json
import os
import tempfile
import unittest
import uuid
from unittest.mock import patch
os.environ.setdefault('AURUM_DATABASE', str(__import__('pathlib').Path(tempfile.gettempdir())/'aurum-module-tests.sqlite3'))
from server import AurumAPI, shared_body
import providers

def document(kind='itinerary'):
    stop_id = str(uuid.uuid4())
    place = {'id':'42','name':'A memorable table','category':'restaurant','city':'Paris','address':'12 Example Street','phone':'','website':'https://example.com','source':'Manual entry','overview':'','latitude':48.85,'longitude':2.35}
    return {'id':str(uuid.uuid4()),'kind':kind,'title':'Paris, thoughtfully','destination':'Paris','description':'A long weekend','dateMode':'dates','startDate':'2026-10-01','endDate':'2026-10-04','visibility':'private','stops':[{'id':stop_id,'name':'Paris','code':'PAR','country':'France','arrival':'2026-10-01','nights':3}], 'events':[{'id':str(uuid.uuid4()),'seriesID':str(uuid.uuid4()),'stopID':stop_id,'day':0,'minute':1140,'place':place,'description':'Dinner','links':['https://example.com'],'cost':{'amount':85.5,'currency':'EUR'}}], 'hotels':[{'id':str(uuid.uuid4()),'place':{**place,'id':'hotel-42','category':'hotel','name':'Example Hotel'},'checkIn':'2026-10-01','checkOut':'2026-10-04','guests':2,'rooms':1,'roomType':'Suite','confirmation':'PRIVATE-123','notes':'Secret arrival instruction','overview':'','cost':{'amount':600,'currency':'EUR'}}], 'flights':[], 'places':[], 'updatedAt':12345678.0}

class APITest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.api = AurumAPI(os.path.join(self.directory.name,'test.sqlite3'))
        self.alice = self.register('alice')
        self.bob = self.register('bob')
        self.carol = self.register('carol')
    def tearDown(self):
        self.directory.cleanup()
    def call(self, method, path, body=None, token=None, peer="test-client"):
        raw = json.dumps(body).encode() if body is not None else b''
        p,_,q = path.partition('?')
        env = {'REQUEST_METHOD':method,'PATH_INFO':p,'QUERY_STRING':q,'CONTENT_LENGTH':str(len(raw)),'CONTENT_TYPE':'application/json','wsgi.input':io.BytesIO(raw),'REMOTE_ADDR':peer}
        if token:
            env['HTTP_AUTHORIZATION'] = 'Bearer '+token
        info = {}
        payload = b''.join(self.api(env,lambda status,headers: info.update(status=int(status.split()[0]),headers=dict(headers))))
        result = json.loads(payload) if info['headers']['Content-Type'].startswith('application/json') else payload.decode()
        return info['status'],result
    def register(self, handle):
        status, response = self.call('POST','/v1/auth/register',{'handle':handle,'name':handle.title(),'password':'Strong-test-password-123'})
        self.assertEqual(status,200,response)
        return response
    def friend(self):
        self.assertEqual(self.call('POST','/v1/friends',{'handle':'bob'},self.alice['token'])[0],200)
        self.assertEqual(self.call('PUT','/v1/friends/'+self.alice['user']['id'],{},self.bob['token'])[0],200)
    def upload(self, d, owner=None):
        response = self.call('PUT','/v1/documents/'+d['id'],d,(owner or self.alice)['token'])
        self.assertEqual(response[0],200,response)
        return response[1]
    def test_flight_endpoints_require_account_outside_loopback(self):
        import flight_provider
        payload = {'flights': [], 'fetchedAt': 1, 'historyEnabled': False, 'message': 'Not connected'}
        with patch.object(flight_provider, 'status', return_value=payload) as provider:
            self.assertEqual(self.call('GET', '/v1/flights/status?q=BA178&date=2026-09-06')[0], 401)
            provider.assert_not_called()
            self.assertEqual(self.call('GET', '/v1/flights/status?q=BA178&date=2026-09-06', peer='127.0.0.1'), (200,payload))
            self.assertEqual(self.call('GET', '/v1/flights/status?q=BA178&date=2026-09-06', token=self.alice['token']), (200,payload))
        with patch.dict(os.environ, {'PUBLIC_BASE_URL':'https://travel.example.com'}):
            self.assertEqual(self.call('GET','/v1/flights/status?q=BA178&date=2026-09-06',peer='127.0.0.1')[0],401)

    def test_google_autocomplete_access_and_rate_limit(self):
        matches = [{'id': 'place-1', 'title': 'The Savoy', 'subtitle': 'London'}]
        with patch.object(providers, 'autocomplete_places', return_value=matches) as provider:
            self.assertEqual(self.call('GET', '/v1/locations/autocomplete?q=Savoy')[0], 401)
            provider.assert_not_called()
            self.assertEqual(self.call('GET', '/v1/locations/autocomplete?q=Savoy', peer='127.0.0.1'), (200, matches))
            self.assertEqual(self.call('GET', '/v1/locations/autocomplete?q=Savoy', token=self.alice['token']), (200, matches))
            for _ in range(59):
                self.assertEqual(self.call('GET', '/v1/locations/autocomplete?q=Savoy', peer='127.0.0.1')[0], 200)
            self.assertEqual(self.call('GET', '/v1/locations/autocomplete?q=Savoy', peer='127.0.0.1')[0], 429)

    def test_google_autocomplete_validation_normalization_and_secret(self):
        raw = {'suggestions': [{'placePrediction': {'placeId': 'abc', 'structuredFormat': {'mainText': {'text': 'The Savoy'}, 'secondaryText': {'text': 'London'}}}}, {'queryPrediction': {'text': 'ignore'}}]}
        with patch.dict(os.environ, {'GOOGLE_PLACES_API_KEY': 'test-secret'}), patch.object(providers, 'request_json', return_value=raw) as request:
            self.assertEqual(providers.autocomplete_places(' Savoy '), [{'id': 'abc', 'title': 'The Savoy', 'subtitle': 'London'}])
            self.assertNotIn('test-secret', request.call_args.args[0])
            self.assertEqual(request.call_args.kwargs['data']['input'], 'Savoy')
            for invalid in ['', 'a', 'x' * 201, None]:
                with self.assertRaises(providers.ProviderError) as caught: providers.autocomplete_places(invalid)
                self.assertEqual(caught.exception.status, 400)
        with patch.dict(os.environ, {'GOOGLE_PLACES_API_KEY': ''}):
            with self.assertRaises(providers.ProviderError): providers.autocomplete_places('Savoy')

    def test_meetings_roundtrip_and_shared_page(self):
        d = document()
        event = d['events'][0]
        event.update(kind='meeting', title='Design <review>', minute=1410, durationMinutes=90, allDay=False, attendees='Alex & Sam')
        event['place']['name'] = ''
        self.upload(d)
        restored = self.call('GET','/v1/documents/'+d['id'],token=self.alice['token'])[1]['document']
        self.assertEqual(restored['events'][0], event)
        with patch.dict(os.environ,{'PUBLIC_BASE_URL':'https://travel.example'}):
            status, link = self.call('POST','/v1/documents/'+d['id']+'/link',{},self.alice['token'])
        status, page = self.call('GET','/s/'+link['url'].rsplit('/',1)[-1])
        self.assertEqual(status,200)
        self.assertIn('Design &lt;review&gt;',page)
        self.assertIn('01:00 (+1 day)',page)
        self.assertIn('Alex &amp; Sam',page)
        event['allDay'] = True
        d['updatedAt'] += 1
        self.upload(d)
        page = self.call('GET','/s/'+link['url'].rsplit('/',1)[-1])[1]
        self.assertIn('All day',page)
        self.assertNotIn('01:00 (+1 day)',page)
    def test_invalid_event_details_rejected(self):
        for fields in [dict(kind='unknown'), dict(kind='meeting',title=' '), dict(durationMinutes=0), dict(durationMinutes=1441), dict(durationMinutes=True), dict(allDay='true')]:
            with self.subTest(fields=fields):
                d = document(); d['events'][0].update(fields)
                self.assertEqual(self.call('PUT','/v1/documents/'+d['id'],d,self.alice['token'])[0],400)
    def test_unified_and_legacy_trips_share_plans_and_journal(self):
        for kind in ['journey', 'itinerary', 'trip']:
            with self.subTest(kind=kind):
                d = document(kind); d['visibility'] = 'public'
                d['places'] = [{'id':str(uuid.uuid4()),'place':{**d['events'][0]['place'],'id':'museum','name':'Memorable museum','category':'museum'},'overall':9.2,'scores':{'Experience':9},'notes':'Beautiful galleries','visitedOn':'2026-10-02','photos':[]}]
                self.upload(d)
                remote = self.call('GET','/v1/documents/'+d['id'],token=self.bob['token'])[1]['document']
                self.assertEqual(remote['events'],d['events']); self.assertEqual(remote['places'],d['places'])
                self.assertEqual(remote['hotels'][0]['confirmation'],'')
                with patch.dict(os.environ,{'PUBLIC_BASE_URL':'https://travel.example'}):
                    _, link = self.call('POST','/v1/documents/'+d['id']+'/link',{},self.alice['token'])
                status, page = self.call('GET','/s/'+link['url'].rsplit('/',1)[-1])
                self.assertEqual(status,200)
                for content in ['A memorable table','Example Hotel','Memorable museum','Beautiful galleries','9.2']:
                    self.assertIn(content,page)
                self.assertNotIn('PRIVATE-123',page)
    def test_unified_trip_can_start_without_route_then_add_plans(self):
        d=document('journey'); original = copy.deepcopy(d)
        d['stops']=[]; d['events']=[]; d['hotels']=[]
        d.pop('startDate'); d.pop('endDate')
        self.upload(d)
        d['stops']=original['stops']; d['events']=original['events']; d['updatedAt']+=1
        self.upload(d)
        restored = self.call('GET','/v1/documents/'+d['id'],token=self.alice['token'])[1]['document']
        self.assertEqual(restored['events'],d['events'])
    def test_auth_and_logout(self):
        self.assertEqual(self.call('GET','/v1/me')[0],401)
        self.assertEqual(self.call('POST','/v1/auth/login',{'handle':'alice','password':'not-the-real-password'})[0],401)
        self.assertEqual(self.call('GET','/v1/me',token=self.alice['token'])[1]['handle'],'alice')
        self.call('POST','/v1/auth/logout',{},self.alice['token'])
        self.assertEqual(self.call('GET','/v1/me',token=self.alice['token'])[0],401)
    def test_owner_only_writes_and_private_reads(self):
        d=document();self.upload(d)
        self.assertEqual(self.call('GET','/v1/documents/'+d['id'],token=self.bob['token'])[0],403)
        self.assertEqual(self.call('PUT','/v1/documents/'+d['id'],d,self.bob['token'])[0],403)
        self.assertEqual(self.call('DELETE','/v1/documents/'+d['id'],token=self.bob['token'])[0],403)
    def test_only_recipient_can_accept_request(self):
        self.call('POST','/v1/friends',{'handle':'bob'},self.alice['token'])
        self.assertEqual(self.call('PUT','/v1/friends/'+self.bob['user']['id'],{},self.alice['token'])[0],403)
        self.assertEqual(self.call('GET','/v1/friends',token=self.bob['token'])[1][0]['incoming'],True)
    def test_friend_feed_redacts_booking_references(self):
        self.friend();d=document();d['visibility']='friends';self.upload(d)
        feed=self.call('GET','/v1/feed',token=self.bob['token'])[1]
        self.assertEqual(len(feed),1)
        self.assertEqual(feed[0]['document']['hotels'][0]['confirmation'],'')
        self.assertEqual(feed[0]['document']['hotels'][0]['notes'],'')
        self.assertEqual(self.call('GET','/v1/documents/'+d['id'],token=self.alice['token'])[1]['document']['hotels'][0]['confirmation'],'PRIVATE-123')
        self.assertEqual(self.call('GET','/v1/feed',token=self.carol['token'])[1],[])
    def test_links_read_only_and_revocable(self):
        d=document();self.upload(d)
        with patch.dict(os.environ,{'PUBLIC_BASE_URL':'https://travel.example'}):
            status,link=self.call('POST','/v1/documents/'+d['id']+'/link',{},self.alice['token'])
        self.assertEqual(status,200)
        path='/s/'+link['url'].rsplit('/',1)[-1]
        status,page=self.call('GET',path)
        self.assertEqual(status,200)
        self.assertIn('Paris, thoughtfully',page)
        self.assertNotIn('PRIVATE-123',page)
        self.assertNotIn('Secret arrival instruction',page)
        self.call('POST','/v1/documents/'+d['id']+'/revoke',{},self.alice['token'])
        self.assertEqual(self.call('GET',path)[0],404)
    def test_no_fake_public_links_without_deployment(self):
        d=document();self.upload(d)
        with patch.dict(os.environ,{'PUBLIC_BASE_URL':''}):
            self.assertEqual(self.call('POST','/v1/documents/'+d['id']+'/link',{},self.alice['token'])[0],503)
    def test_group_acl_sharing_and_revocation(self):
        self.friend()
        status,chat=self.call('POST','/v1/conversations',{'name':'Paris plans','members':[self.bob['user']['id']]},self.alice['token'])
        self.assertEqual(status,200)
        path='/v1/conversations/'+chat['id']+'/messages'
        self.assertEqual(self.call('GET',path,token=self.carol['token'])[0],403)
        d=document();self.upload(d)
        self.assertEqual(self.call('POST',path,{'text':'Let’s go','documentID':d['id']},self.alice['token'])[0],200)
        self.assertEqual(len(self.call('GET',path,token=self.bob['token'])[1]),1)
        self.assertEqual(self.call('GET','/v1/documents/'+d['id'],token=self.bob['token'])[0],200)
        self.call('POST','/v1/documents/'+d['id']+'/revoke',{},self.alice['token'])
        self.assertEqual(self.call('GET','/v1/documents/'+d['id'],token=self.bob['token'])[0],403)
    def test_cannot_invite_nonfriends(self):
        self.assertEqual(self.call('POST','/v1/conversations',{'name':'Uninvited','members':[self.bob['user']['id']]},self.alice['token'])[0],403)
    def test_friend_removal_revokes_feed_access(self):
        self.friend();d=document();d['visibility']='friends';self.upload(d)
        self.call('DELETE','/v1/friends/'+self.bob['user']['id'],{},self.alice['token'])
        self.assertEqual(self.call('GET','/v1/documents/'+d['id'],token=self.bob['token'])[0],403)
    def test_stale_copy_conflict(self):
        d=document();self.upload(d);d['updatedAt']-=1
        self.assertEqual(self.call('PUT','/v1/documents/'+d['id'],d,self.alice['token'])[0],409)
    def test_validation_invalid_dates_events_money(self):
        mutations=[lambda d:d['events'][0].update(day=50),lambda d:d['events'][0].update(cost={'amount':-5,'currency':'EUR'}),lambda d:d['hotels'][0].update(checkOut='2026-09-01'),lambda d:d['events'][0]['place'].update(latitude=1000),lambda d:d['events'][0].update(links=['javascript:alert(1)'])]
        for mutate in mutations:
            d=document();mutate(d)
            self.assertEqual(self.call('PUT','/v1/documents/'+d['id'],d,self.alice['token'])[0],400)
    def test_public_trip_and_private_transition(self):
        d=document('trip');d['visibility']='public';self.upload(d)
        self.assertEqual(self.call('GET','/v1/documents/'+d['id'],token=self.carol['token'])[0],200)
        d['visibility']='private';d['updatedAt']+=1;self.upload(d)
        self.assertEqual(self.call('GET','/v1/documents/'+d['id'],token=self.carol['token'])[0],403)
    def test_html_escapes_untrusted_content(self):
        d=document();d['title']='<script>alert(1)</script>';self.upload(d)
        with patch.dict(os.environ,{'PUBLIC_BASE_URL':'https://travel.example'}):
            _,link=self.call('POST','/v1/documents/'+d['id']+'/link',{},self.alice['token'])
        _,page=self.call('GET','/s/'+link['url'].rsplit('/',1)[-1])
        self.assertNotIn('<script>',page)
        self.assertIn('&lt;script&gt;',page)
    def test_provider_keys_are_never_returned(self):
        with patch.dict(os.environ,{'TRIPADVISOR_API_KEY':'do-not-expose','OPENAI_API_KEY':'do-not-expose-ai'}):
            status,response=self.call('GET','/v1/status')
        self.assertEqual(status,200)
        self.assertTrue(response['tripadvisor'])
        self.assertNotIn('do-not-expose',json.dumps(response))
    def test_missing_provider_is_explicit(self):
        with patch.dict(os.environ,{'TRIPADVISOR_API_KEY':''}):
            status,response=self.call('GET','/v1/places/search?q=Paris&category=hotels',token=self.alice['token'])
        self.assertEqual(status,503)
        self.assertIn('not connected',response['error'])
    def test_ai_recommendations_only_return_known_provider_ids(self):
        candidates=[{'id':'1','name':'Museum','category':'attraction'},{'id':'2','name':'Park','category':'attraction'}]
        with patch.object(providers,'search_places',return_value=candidates),patch.object(providers,'place_details',side_effect=lambda i:next(p for p in candidates if p['id']==i)),patch.object(providers,'ai_text',return_value={'text':'Visit the museum.','place_ids':['1','made-up']}):
            result=providers.recommend('Paris','Art')
        self.assertEqual([p['id'] for p in result['places']],['1'])

if __name__=='__main__':
    unittest.main()
