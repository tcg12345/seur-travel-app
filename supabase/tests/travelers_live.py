"""Opt-in profile CRUD/privacy smoke. Disposable accounts only; no hotel/provider calls."""
import argparse, json, secrets, uuid
from pathlib import Path
from hotel_rates_live import call

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--saved-travelers',action='store_true',required=True);parser.parse_args()
    users=[]
    report={'profilesCreated':0,'bookingsCreated':0}
    try:
        call('GET','/v1/travelers',expected=401)
        for _ in range(2): users.append(call('POST','/v1/auth/register',{'handle':'traveler_qa_'+secrets.token_hex(5),'name':'Traveler QA','password':secrets.token_urlsafe(30)}))
        a,b=[u['token'] for u in users];p,q=str(uuid.uuid4()),str(uuid.uuid4())
        details={'firstName':'Test','lastName':'Traveler','email':'test@example.test','phone':'+12125550123','nationality':'CA','expectedVersion':0,'isDefault':False}
        assert call('GET','/v1/travelers',token=a)['profiles']==[]
        rows=call('PUT','/v1/travelers/'+p,details,a)['profiles'];assert len(rows)==1 and rows[0]['isDefault'] and rows[0]['version']==1
        assert 'private_payload' not in rows[0] and 'owner' not in rows[0];report['profilesCreated']+=1
        assert call('GET','/v1/travelers',token=b)['profiles']==[]
        call('PUT','/v1/travelers/'+p,{**details,'expectedVersion':1},b,expected=409)
        assert call('DELETE','/v1/travelers/'+p,{'expectedVersion':1},b)['profiles']==[]
        rows=call('PUT','/v1/travelers/'+q,{**details,'firstName':'Companion','isDefault':True},a)['profiles'];report['profilesCreated']+=1
        assert rows[0]['id']==q and rows[0]['isDefault']; first=next(r for r in rows if r['id']==p);assert first['version']==2 and not first['isDefault']
        call('PUT','/v1/travelers/'+p,{**details,'expectedVersion':1},a,expected=409)
        call('DELETE','/v1/travelers/'+p,{'expectedVersion':1},a,expected=409)
        rows=call('PUT','/v1/travelers/'+p,{**details,'expectedVersion':2,'nationality':'US','firstName':'Updated'},a)['profiles'];assert next(r for r in rows if r['id']==p)['nationality']=='US'
        call('PUT','/v1/travelers/'+p,{**details,'expectedVersion':3,'nationality':'XX'},a,expected=400)
        rows=call('DELETE','/v1/travelers/'+q,{'expectedVersion':1},a)['profiles'];assert len(rows)==1 and rows[0]['id']==p and rows[0]['isDefault'] and rows[0]['version']==4
        assert call('GET','/v1/travelers',token=a)['profiles']==rows
        report.update(crossAccountIsolated=True,staleWritesRejected=True,defaultReassigned=True,nationalityValidated=True,profileReadsVerified=True)
        print('PASS: saved traveler create/read/edit/delete, defaults, conflicts and account isolation')
    finally:
        for user in users:call('DELETE','/v1/account',{},user['token'])
        report['temporaryAccountsDeleted']=len(users)
        Path('work').mkdir(exist_ok=True);Path('work/travelers-validation.json').write_text(json.dumps(report,indent=2))
        print('Temporary accounts deleted; zero provider calls or bookings')
if __name__=='__main__':main()
