"""Check optional stats metadata through private cloud save/restore; no provider calls."""
import json,secrets,uuid,urllib.request,urllib.error
from pathlib import Path
BASE='https://bwrodcxmdzrpyrshrlfd.supabase.co/functions/v1/travel-api'
def call(method,path,body=None,token=None,expected=200):
 req=urllib.request.Request(BASE+path,data=json.dumps(body).encode() if body is not None else None,method=method,headers={'Content-Type':'application/json',**({'Authorization':'Bearer '+token} if token else {})})
 try:
  with urllib.request.urlopen(req,timeout=60) as response:status,data=response.status,response.read()
 except urllib.error.HTTPError as error:status,data=error.code,error.read()
 assert status==expected,(method,status,data[:150])
 return json.loads(data)
user=None
try:
 user=call('POST','/v1/auth/register',{'handle':'stats_qa_'+secrets.token_hex(5),'name':'Stats QA','password':secrets.token_urlsafe(30)})
 token=user['token'];doc=json.loads((Path(__file__).parents[2]/'iOS/Aurum/Resources/TripTemplates.json').read_text())[0]
 doc['id']=str(uuid.uuid4());doc['isTemplate']=False;doc.pop('templateMeta',None);doc['visibility']='private'
 doc['stops'][0]['countryCode']='MC';doc['hotels'][0]['place']['brand']='Monte-Carlo SBM'
 path='/v1/documents/'+doc['id'];call('PUT',path,doc,token)
 restored=call('GET',path,token=token)['document']
 assert restored['stops'][0]['countryCode']=='MC' and restored['hotels'][0]['place']['brand']=='Monte-Carlo SBM'
 doc['stops'][0]['countryCode']='invalid';call('PUT',path,doc,token,expected=400)
 assert call('GET',path,token=token)['document']['stops'][0]['countryCode']=='MC'
 print('PASS: optional country codes and brands survive private cloud save/restore; malformed codes do not overwrite saved data')
finally:
 if user:call('DELETE','/v1/account',{},user['token']);print('Removed disposable stats account')
