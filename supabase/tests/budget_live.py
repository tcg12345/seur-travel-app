"""One disposable account: daily rates, ledger/photo roundtrip and account cleanup.
No messages, payments, paid providers or changes to existing accounts.
"""
import base64
import copy
import json
import os
from pathlib import Path
import secrets
import time
import urllib.error
import urllib.request
import uuid

BASE = os.getenv('SEUR_TEST_URL', 'https://bwrodcxmdzrpyrshrlfd.supabase.co/functions/v1/travel-api')

def call(method, path, body=None, token=None, expected=200):
    req = urllib.request.Request(BASE + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={'Content-Type': 'application/json', **({'Authorization': 'Bearer ' + token} if token else {})})
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            status, data = response.status, response.read()
    except urllib.error.HTTPError as response:
        status, data = response.code, response.read()
    assert status in (expected if isinstance(expected, tuple) else (expected,)), f'{method} {path.split("?")[0]}: expected {expected}, got {status}'
    return json.loads(data)

def main():
    call('GET', '/v1/exchange-rates', expected=401)
    user = None
    try:
        handle, password = 'budget_qa_' + secrets.token_hex(5), secrets.token_urlsafe(24)
        user = call('POST', '/v1/auth/register', {'handle': handle, 'name': 'Temporary budget QA', 'password': password})
        token = user['token']
        rates = call('GET', '/v1/exchange-rates', token=token)
        assert rates['base'] == 'USD' and rates['rates']['USD'] == 1
        assert all(rates['rates'][currency] > 0 for currency in ['EUR', 'GBP', 'JPY', 'AED'])
        assert call('GET', '/v1/exchange-rates', token=token)['fetchedAt'] == rates['fetchedAt']
        a, b, stop = user['user']['id'], str(uuid.uuid4()), str(uuid.uuid4())
        place = {'id': 'qa-place', 'name': 'QA dinner', 'category': 'restaurant', 'city': 'Paris', 'address': '', 'phone': '', 'website': '', 'source': 'QA', 'overview': ''}
        photo = {'id': str(uuid.uuid4()), 'jpeg': base64.b64encode(Path('iOS/Aurum/Assets.xcassets/paris.imageset/paris.jpg').read_bytes()).decode()}
        d = {'id': str(uuid.uuid4()), 'kind': 'journey', 'title': 'Temporary budget test', 'destination': 'Paris', 'description': '', 'dateMode': 'dates', 'startDate': '2026-10-01', 'endDate': '2026-10-04', 'visibility': 'private', 'updatedAt': time.time(),
            'homeCurrency': 'USD', 'budgetTarget': 1000, 'companions': [{'id': a, 'name': 'Alex'}, {'id': b, 'name': 'Blair'}],
            'stops': [{'id': stop, 'name': 'Paris', 'arrival': '2026-10-01', 'nights': 3}],
            'events': [{'id': str(uuid.uuid4()), 'seriesID': str(uuid.uuid4()), 'stopID': stop, 'day': 0, 'minute': 720, 'place': place, 'description': '', 'links': [], 'isDone': True, 'cost': {'amount': 100, 'currency': 'EUR', 'paidBy': a, 'splitBetween': [a, b]}}],
            'hotels': [], 'flights': [], 'places': [{'id': str(uuid.uuid4()), 'place': place, 'overall': 0, 'scores': {}, 'notes': '', 'priceRange': '', 'photos': [photo]}]}
        path = '/v1/documents/' + d['id']
        call('PUT', path, d, token)
        assert call('GET', path, token=token)['document'] == d
        summary = call('GET', '/v1/documents', token=token)[0]
        assert summary['isSummary'] and summary['document']['budgetTarget'] == 1000
        assert summary['document']['places'][0]['photos'] == []
        bad = copy.deepcopy(d); bad['events'][0]['cost']['splitBetween'] = [str(uuid.uuid4())]
        call('PUT', path, bad, token, expected=400)
        extra = call('POST', '/v1/auth/login', {'handle': handle, 'password': password})
        try:
            call('DELETE', '/v1/account', {}, token)
        except (TimeoutError, urllib.error.URLError):
            # A lost DELETE response is success only if the fresh session is revoked.
            call('GET', '/v1/me', token=token, expected=401)
        user = None
        call('GET', '/v1/me', token=extra['token'], expected=401)
        print('PASS: authenticated daily rate cache, budget/split/photo roundtrip, validation and account deletion with session revocation')
    finally:
        if user:
            call('DELETE', '/v1/account', {}, user['token'], expected=(200, 401))
            print('Removed temporary budget QA account')

if __name__ == '__main__':
    main()
