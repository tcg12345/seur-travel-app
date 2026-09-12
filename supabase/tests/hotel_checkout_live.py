"""Opt-in: one no-charge LiteAPI sandbox booking with synthetic contact details.
Never use production keys. No real payment method or real guest is submitted.
"""
import argparse, datetime, json, secrets, time, uuid
from pathlib import Path
from hotel_rates_live import call

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--sandbox-booking',action='store_true',required=True);parser.parse_args()
    users=[];report={'environment':'sandbox','bookingsRequested':0,'paymentMethod':'sandbox simulation','realCharges':0}
    try:
        status=call('GET','/v1/status');assert status['hotelSandboxCheckout'] and status['hotelBooking'] is False
        for _ in range(2):users.append(call('POST','/v1/auth/register',{'handle':'checkout_qa_'+secrets.token_hex(5),'name':'Checkout QA','password':secrets.token_urlsafe(30)}))
        a,b=[u['token'] for u in users]
        start=datetime.date.today()+datetime.timedelta(days=30)
        page=call('POST','/v1/hotel-rates',{'hotelIds':['liteapi:lp1aae8'],'checkin':str(start),'checkout':str(start+datetime.timedelta(days=3)),'currency':'USD','guestNationality':'US','occupancies':[{'adults':2,'children':[]}],'detail':True},a)
        offer=next(o for h in page['hotels'] for o in h['offers'] if o['total'] and all('NUITEE_PAY' in r['paymentTypes'] for r in o['rooms']))
        request={'id':str(uuid.uuid4()),'quote':offer['quote'],'hotelName':'Mandarin Oriental, Bangkok','guest':{'firstName':'Sandbox','lastName':'Tester','email':'seur-checkout@example.test','phone':'+12125550123'}}
        checkout=call('POST','/v1/hotel-checkouts',request,a);assert checkout['state']=='review',checkout['state']
        repeat=call('POST','/v1/hotel-checkouts',request,a);assert repeat['id']==checkout['id'] and repeat['quoteVersion']==checkout['quoteVersion']
        path='/v1/hotel-checkouts/'+checkout['id']
        call('GET',path,token=b,expected=404)
        call('POST',path+'/confirm',{'quoteVersion':str(uuid.uuid4()),'acceptTestBooking':True},a,expected=409)
        confirm={'quoteVersion':checkout['quoteVersion'],'acceptTestBooking':True}
        approved=call('POST',path+'/confirm',confirm,a);assert approved['state']=='queued'
        repeat=call('POST',path+'/confirm',confirm,a);assert repeat['id']==approved['id']
        report.update({'checkoutId':checkout['id'],'bookingsRequested':1,'duplicateCreateRecovered':True,'duplicateConfirmRecovered':True,'crossOwnerRejected':True,'staleQuoteRejected':True,'prebookChanged':checkout['review']['changed']})
        print('Saved checkout, verified ownership and duplicate final intent; waiting for durable worker',flush=True)
        last=None
        for _ in range(30):
            time.sleep(5);checkout=call('GET',path,token=a)
            if checkout['state']!=last:print('State:',checkout['state'],flush=True);last=checkout['state']
            if checkout['state'] in ['confirmed','needs_support']:break
        report['verificationPassed']=checkout['state']=='confirmed';report['issue']=checkout['review'].get('issue');report['finalState']=checkout['state'];report['providerBookingId']=checkout.get('booking',{}).get('id') if checkout.get('booking') else None
        Path('work').mkdir(exist_ok=True);Path('work/hotel-checkout-validation.json').write_text(json.dumps(report,indent=2))
        assert checkout['state']=='confirmed','Provider confirmation still pending; retained checkout reference in report'
        assert checkout['paymentState']=='test_no_charge'
        assert any(c['id']==checkout['id'] for c in call('GET','/v1/hotel-checkouts',token=a)['checkouts'])
        print('PASS: provider-confirmed no-charge sandbox booking; one durable attempt',flush=True)
    finally:
        for user in users:call('DELETE','/v1/account',{},user['token'])
        print('Deleted temporary accounts; detached operational test record retained',flush=True)
if __name__=='__main__':main()
