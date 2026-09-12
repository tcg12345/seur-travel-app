"""Opt-in, bounded sandbox rate acceptance. No prebook, payment or booking calls."""
import argparse, datetime, json, secrets, time, urllib.request, urllib.error
from decimal import Decimal
from pathlib import Path
BASE = 'https://bwrodcxmdzrpyrshrlfd.supabase.co/functions/v1/travel-api'
def call(method, path, body=None, token=None, expected=200):
    request = urllib.request.Request(BASE + path, data=json.dumps(body).encode() if body is not None else None, method=method, headers={'Content-Type':'application/json', **({'Authorization':'Bearer ' + token} if token else {})})
    try:
        with urllib.request.urlopen(request, timeout=40) as response: status, raw = response.status, response.read()
    except urllib.error.HTTPError as error: status, raw = error.code, error.read()
    assert status == expected, f'{method} {path}: expected {expected}, received {status}'
    return json.loads(raw)
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--sandbox-rates',action='store_true',required=True);parser.add_argument('--quick',action='store_true');args=parser.parse_args()
    users=[]; report={'scenarios':[],'quotesInspected':0,'bookingsCreated':0}
    try:
        status=call('GET','/v1/status'); assert status['hotelRates'] and status['hotelEnvironment']=='sandbox' and status['hotelBooking'] is False
        for _ in range(2): users.append(call('POST','/v1/auth/register',{'handle':'rates_qa_'+secrets.token_hex(5),'name':'Rates QA','password':secrets.token_urlsafe(30)}))
        a,b=[u['token'] for u in users]
        start=datetime.date.today()+datetime.timedelta(days=30)
        base={'hotelIds':['liteapi:lp1aae8','liteapi:lp7246c','liteapi:lp2a32f'],'checkin':str(start),'checkout':str(start+datetime.timedelta(days=3)),'currency':'USD','guestNationality':'US','occupancies':[{'adults':2,'children':[]}],'detail':False}
        call('POST','/v1/hotel-rates',base,expected=401)
        call('POST','/v1/hotel-rates',{**base,'occupancies':[{'adults':2,'children':[-1]}]},a,expected=400)
        scenarios=[('three-hotel-summary',base),('single-hotel-rooms',{**base,'hotelIds':['liteapi:lp1aae8'],'detail':True}),('family-two-rooms',{**base,'hotelIds':['liteapi:lp1aae8'],'occupancies':[{'adults':2,'children':[]},{'adults':1,'children':[6]}],'detail':True}),('euro',{**base,'currency':'EUR'}),('yen',{**base,'hotelIds':['liteapi:lp1aae8'],'currency':'JPY'})]
        if args.quick: scenarios=scenarios[:1]
        quote=None
        for name,payload in scenarios:
            time.sleep(1)
            page=call('POST','/v1/hotel-rates',payload,a)
            assert page['environment']=='sandbox' and page['checkoutEnabled'] is False
            assert page['criteria']['occupancies']==payload['occupancies']
            offers=[o for h in page['hotels'] for o in h['offers']]
            for o in offers:
                assert len(o['rooms'])==len(payload['occupancies'])
                assert o['base']['currency']==payload['currency']
                if o['total']:
                    fee_sum=sum((Decimal(f['charge']['amount']) for f in o['fees'] if not f['included']),Decimal(0))
                    assert Decimal(o['total']['amount'])==Decimal(o['base']['amount'])+fee_sum
                quote=quote or o['quote']
            report['scenarios'].append({'name':name,'hotelCount':len(page['hotels']),'offers':len(offers),'statuses':[h['status'] for h in page['hotels']],'currency':payload['currency'],'completeTotals':sum(o['total'] is not None for o in offers),'publicFloorAdjustmentsNeeded':sum(not o['publicPriceEligible'] for o in offers)})
            print(name, 'offers',len(offers),'statuses',[h['status'] for h in page['hotels']],flush=True)
        assert quote,'No sandbox rates returned in acceptance sample'
        review=call('POST','/v1/hotel-quotes/inspect',{'quote':quote},a);assert isinstance(review['checkoutEnabled'],bool) and 'supplierOfferId' not in review
        call('POST','/v1/hotel-quotes/inspect',{'quote':quote},b,expected=404)
        call('POST','/v1/hotel-quotes/inspect',{'quote':quote[:30]+'!'+quote[31:]},a,expected=400)
        report['quotesInspected']=1;report['unauthenticatedRejected']=True;report['crossAccountRejected']=True;report['tamperedRejected']=True
        Path('work').mkdir(exist_ok=True);Path('work/hotel-rates-final-check.json' if args.quick else 'work/hotel-rates-validation.json').write_text(json.dumps(report,indent=2))
        print('PASS: sandbox rates, fee totals, quote ownership and tamper rejection; zero bookings')
    finally:
        for user in users: call('DELETE','/v1/account',{},user['token'])
        print('Deleted temporary rate-validation accounts')
if __name__=='__main__':main()
