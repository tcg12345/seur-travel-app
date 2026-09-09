"""Live template contract test; one temporary account, removed in finally. No provider calls."""
import json, secrets, time, urllib.request, urllib.error, uuid
from pathlib import Path
BASE='https://bwrodcxmdzrpyrshrlfd.supabase.co/functions/v1/travel-api'
def call(method,path,body=None,token=None,expected=200,retried=False):
    req=urllib.request.Request(BASE+path,data=json.dumps(body).encode() if body is not None else None,method=method,headers={'Content-Type':'application/json',**({'Authorization':'Bearer '+token} if token else {})})
    try:
        with urllib.request.urlopen(req,timeout=40) as r: status,data=r.status,r.read()
    except urllib.error.HTTPError as e: status,data=e.code,e.read()
    except (TimeoutError,urllib.error.URLError):
        if method=="GET" and not retried: return call(method,path,body,token,expected,True)
        raise
    assert status==expected,(method,path,status,data[:200])
    return json.loads(data)
public=call('GET','/v1/templates'); assert len(public)>=10 and all(x['isSummary'] for x in public)
assert all(not x['document']['events'] for x in public)
paris=call('GET','/v1/templates?city=Paris&tags=art'); assert len(paris)==1
assert call('GET','/v1/templates?city=Copenhagen&tags=beach')==[]
call('GET','/v1/templates?tags=invalid!',expected=400)
full=call('GET','/v1/templates/'+paris[0]['id']); assert full['document']['events'] and full['document']['hotels']
user=None
try:
    handle='template_qa_'+secrets.token_hex(5)
    user=call('POST','/v1/auth/register',{'handle':handle,'name':'Template QA','password':secrets.token_urlsafe(30)})
    token=user['token']; doc=json.loads((Path(__file__).parents[2]/'iOS/Aurum/Resources/TripTemplates.json').read_text())[0]
    doc['id']=str(uuid.uuid4()); doc['visibility']='private'; doc['updatedAt']=time.time()
    doc['hotels'][0]['confirmation']='PRIVATE-QA-REF'; doc['hotels'][0]['notes']='PRIVATE-QA-NOTE'
    doc['events'][0]['attendees']='PRIVATE-QA-GUEST'; doc['templateMeta']['authorHandle']='forged'; doc['templateMeta']['cloneCount']=999
    path='/v1/documents/'+doc['id']; saved=call('PUT',path,doc,token)
    assert 'PRIVATE-QA' not in json.dumps(saved)
    call('GET','/v1/templates/'+doc['id'],expected=404)
    doc['visibility']='public'; doc['updatedAt']+=1; call('PUT',path,doc,token)
    template=call('GET','/v1/templates/'+doc['id']); assert template['document']['templateMeta']['authorHandle']==handle
    assert template['document']['templateMeta']['cloneCount']==0
    clone=str(uuid.uuid4())
    call('POST','/v1/templates/'+doc['id']+'/uses',{'cloneID':clone},expected=401)
    for _ in range(2): call('POST','/v1/templates/'+doc['id']+'/uses',{'cloneID':clone},token)
    assert call('GET','/v1/templates/'+doc['id'])['document']['templateMeta']['cloneCount']==1
    doc['visibility']='private'; doc['updatedAt']+=1; call('PUT',path,doc,token)
    call('GET','/v1/templates/'+doc['id'],expected=404)
    print('PASS: public summaries, filters, full plans, sanitization, author identity, idempotent counts and withdrawal')
finally:
    if user: call('DELETE','/v1/account',{},user['token']); print('Removed temporary template test account')
