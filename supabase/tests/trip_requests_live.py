"""Disposable-account trip request checks. No messages to real users or paid providers."""
import json,secrets,uuid,urllib.request,urllib.error
from pathlib import Path
BASE='https://bwrodcxmdzrpyrshrlfd.supabase.co/functions/v1/travel-api'
def call(method,path,body=None,user=None,expected=200):
    headers={'Content-Type':'application/json'}
    if user: headers['Authorization']='Bearer '+user['token']
    req=urllib.request.Request(BASE+path,data=json.dumps(body).encode() if body is not None else None,method=method,headers=headers)
    try:
        with urllib.request.urlopen(req,timeout=60) as response: status,data=response.status,response.read()
    except urllib.error.HTTPError as error: status,data=error.code,error.read()
    assert status==expected,(method,path,status,data[:200])
    return json.loads(data)
users=[]
def register(name):
    user=call('POST','/v1/auth/register',{'handle':'request_qa_'+secrets.token_hex(5),'name':name,'password':secrets.token_urlsafe(30)})
    users.append(user);return user

def befriend(a,b):
    call('POST','/v1/friends',{'handle':b['user']['handle']},a)
    call('PUT','/v1/friends/'+a['user']['id'],{},b)
try:
    a,b,c=register('Request QA A'),register('Request QA B'),register('Request QA outsider')
    befriend(a,b)
    chat=call('POST','/v1/conversations',{'name':'Trip request QA','members':[b['user']['id']]},a)
    assert call('POST','/v1/conversations',{'name':'Same friend','members':[b['user']['id']]},a)['id']==chat['id']
    path='/v1/conversations/'+chat['id']+'/messages'
    request={'text':'What did you do in Tokyo?','tripRequest':{'city':' Tokyo ','month':'2027-03','unexpected':'drop this'}}
    msg=call('POST',path,request,a)
    assert msg['tripRequest']=={'city':'Tokyo','month':'2027-03'}
    assert call('GET',path,user=b)[0]['id']==msg['id']
    assert call('GET','/v1/conversations',user=b)[0]['pendingRequests']==1
    assert call('GET','/v1/conversations',user=a)[0]['pendingRequests']==0
    call('GET',path,user=c,expected=403);call('POST',path,request,c,expected=403)
    for bad in [{'city':'Tokyo','month':'2027-13'}, {'city':'','month':'2027-03'}, {'city':7,'month':'2027-03'}, {'city':'Tokyo','month':202703}]:
        call('POST',path,{'text':'Invalid','tripRequest':bad},a,expected=400)
    call('POST',path,{'text':'Missing attachment','replyTo':msg['id']},b,expected=400)
    seed=json.loads((Path(__file__).parents[2]/'iOS/Aurum/Resources/TripTemplates.json').read_text())[0]
    doc=json.loads(json.dumps(seed));doc['id']=str(uuid.uuid4());doc['isTemplate']=False;doc.pop('templateMeta',None);doc['visibility']='private'
    doc['hotels'][0]['confirmation']='PRIVATE-REF';doc['hotels'][0]['notes']='PRIVATE-BOOKING-NOTE'
    call('PUT','/v1/documents/'+doc['id'],doc,b)
    call('GET','/v1/documents/'+doc['id'],user=a,expected=403)
    call('POST',path,{'text':'Forged owner','replyTo':msg['id'],'documentID':doc['id']},a,expected=400)
    call('POST',path,{**request,'documentID':doc['id']},b,expected=400)
    reply=call('POST',path,{'text':'Here is my itinerary','replyTo':msg['id'],'documentID':doc['id']},b)
    assert reply['replyTo']==msg['id'] and reply['documentIsTemplate'] is False
    assert call('GET','/v1/conversations',user=b)[0]['pendingRequests']==0
    shared=call('GET','/v1/documents/'+doc['id'],user=a)['document']
    assert 'PRIVATE-REF' not in json.dumps(shared) and 'PRIVATE-BOOKING-NOTE' not in json.dumps(shared)
    call('GET','/v1/documents/'+doc['id'],user=c,expected=403)
    template=json.loads(json.dumps(seed));template['id']=str(uuid.uuid4());template['visibility']='public'
    call('PUT','/v1/documents/'+template['id'],template,b)
    reply=call('POST',path,{'text':'Or use this template','replyTo':msg['id'],'documentID':template['id']},b)
    assert reply['documentIsTemplate'] is True
    assert call('GET','/v1/documents/'+template['id'],user=a)['document']['isTemplate'] is True
    normal=call('POST',path,{'text':'Thanks!'},a);assert normal['tripRequest'] is None and normal['replyTo'] is None
    call('POST',path,{'text':'Wrong target','replyTo':normal['id'],'documentID':doc['id']},b,expected=400)
    befriend(a,c);befriend(b,c)
    other=call('POST','/v1/conversations',{'name':'Separate group','members':[b['user']['id'],c['user']['id']]},a)
    call('POST','/v1/conversations/'+other['id']+'/messages',{'text':'Wrong conversation','replyTo':msg['id'],'documentID':doc['id']},b,expected=400)
    call('DELETE','/v1/friends/'+b['user']['id'],{},a)
    call('POST',path,request,a,expected=403)
    call('POST',path,{'text':'Revoked friendship','replyTo':msg['id'],'documentID':doc['id']},b,expected=403)
    print('PASS: private request, exact DM reuse, pending/answered counts, trip and template replies, redaction, legacy messages, validation, membership, reply scoping and friendship revocation')
finally:
    for user in reversed(users): call('DELETE','/v1/account',{},user)
    print('Removed all disposable request accounts')
