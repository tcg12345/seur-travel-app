"""Photo-scope and revocation test using disposable accounts; no paid providers."""
import json,secrets,uuid,urllib.request,urllib.error
from pathlib import Path
BASE='https://bwrodcxmdzrpyrshrlfd.supabase.co/functions/v1/travel-api'
def call(method,path,body=None,token=None,status=200,raw=False):
 req=urllib.request.Request(BASE+path,data=json.dumps(body).encode() if body is not None else None,method=method,headers={'Content-Type':'application/json',**({'Authorization':'Bearer '+token} if token else {})})
 try:
  with urllib.request.urlopen(req,timeout=60) as r: code,data=r.status,r.read()
 except urllib.error.HTTPError as e: code,data=e.code,e.read()
 assert code==status,(method,code,status,data[:120])
 return data if raw else json.loads(data)
users=[]
try:
 for _ in range(2):users.append(call('POST','/v1/auth/register',{'handle':'recap_qa_'+secrets.token_hex(5),'name':'Recap QA','password':secrets.token_urlsafe(30)}))
 a,b=[u['token'] for u in users]
 d=json.loads((Path(__file__).parents[2]/'iOS/Aurum/Resources/TripTemplates.json').read_text())[0]
 d['id']=str(uuid.uuid4());d['isTemplate']=False;d.pop('templateMeta',None);d['visibility']='private'
 d['hotels'][0]['confirmation']='PRIVATE-REF';d['hotels'][0]['notes']='PRIVATE-NOTE';d['events'][0]['attendees']='PRIVATE-GUEST'
 one,two=str(uuid.uuid4()),str(uuid.uuid4())
 d['places']=[{'id':str(uuid.uuid4()),'place':{'id':'test','name':'A table','category':'restaurant','city':'Monaco','source':'Manual entry','phone':'PRIVATE-PHONE'},'overall':9,'scores':{},'notes':'PRIVATE-NOTE','priceRange':'','visitedOn':'2000-01-01','michelinStars':3,'photos':[{'id':one,'jpeg':'/9j/AA=='},{'id':two,'jpeg':'/9j/Ag=='}]}]
 p={'document':d,'selectedPhotoIDs':[one],'mapJPEG':'/9j/BA=='}
 call('POST','/v1/recaps',p,status=401)
 link=call('POST','/v1/recaps',p,a)['url'];path=link.removeprefix(BASE)
 snapshot=call('GET',path+'&format=json');assert 'PRIVATE-' not in json.dumps(snapshot)
 assert snapshot['stats']['rated']==1 and snapshot['stats']['stars']==3
 assert snapshot['places'][0]['photos']==[{'id':one}]
 assert two not in json.dumps(snapshot)
 assert call('GET',path+'&asset='+one,raw=True)==bytes([255,216,255,0])
 call('GET',path+'&asset='+two,status=404)
 assert 'PRIVATE-' not in json.dumps(call('GET',path.split('?')[0]+'?format=json'))
 call('DELETE','/v1/recaps/'+d['id'],token=b)
 assert call('GET',path+'&format=json')['title']==d['title']
 assert call('GET','/v1/documents',token=a)==[],'Recap published the full trip'
 call('DELETE','/v1/recaps/'+d['id'],token=a)
 call('GET',path+'&format=json',status=404);call('GET',path+'&asset='+one,status=404)
 # An existing source becoming private revokes both the snapshot and its media.
 d['visibility']='public';call('PUT','/v1/documents/'+d['id'],d,a)
 link2=call('POST','/v1/recaps',p,a)['url'].removeprefix(BASE)
 call('POST','/v1/recaps',p,b,status=403)
 d['visibility']='private';d['updatedAt']+=1;call('PUT','/v1/documents/'+d['id'],d,a)
 call('GET',link2+'&format=json',status=404)
 print('PASS: account checks, independent snapshots, selected-only media, format bypass protection, owner-only revocation and source privacy withdrawal')
finally:
 for u in users:call('DELETE','/v1/account',{},u['token'])
 print('Removed disposable recap accounts and media')
