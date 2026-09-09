import datetime as dt
import os
import unittest
from unittest.mock import patch
import flight_provider as f
from providers import ProviderError

class FlightProviderTests(unittest.TestCase):
    def setUp(self):
        f._cache.clear()
        self.day = dt.datetime.now(dt.timezone.utc).date()
    def row(self, **kwargs):
        return {'fa_flight_id':'BAW178-test-1','ident_iata':'BA178','origin':{'code_iata':'JFK','timezone':'America/New_York'}, 'destination':{'code_iata':'LHR','timezone':'Europe/London'}, 'scheduled_out':self.day.isoformat()+'T22:00:00Z', 'scheduled_in':(self.day+dt.timedelta(days=1)).isoformat()+'T05:00:00Z', 'estimated_in':(self.day+dt.timedelta(days=1)).isoformat()+'T05:35:00Z', 'arrival_delay':2100, **kwargs}
    def test_missing_credentials_and_validation(self):
        with patch.dict(os.environ, {'FLIGHTAWARE_API_KEY':''}):
            with self.assertRaises(ProviderError): f.status('BA178',self.day.isoformat())
        for ident, day in [('../secret','2026-09-06'),('BA178','broken'),('',self.day.isoformat())]:
            with self.assertRaises(ProviderError) as e: f.status(ident,day)
            self.assertEqual(e.exception.status,400)
    def test_local_departure_date_and_optional_fields(self):
        row = self.row(scheduled_out=(self.day+dt.timedelta(days=1)).isoformat()+'T02:00:00Z')
        self.assertEqual(f.local_day(row),self.day)
        mapped=f.normalized(row)
        self.assertEqual(mapped['arrivalDelay'],2100)
        self.assertNotIn('gateOrigin',mapped)
        self.assertEqual(mapped['origin'],'JFK')
    def test_runway_estimates_are_preserved(self):
        mapped = f.normalized(self.row(estimated_off='2026-09-08T01:27:00Z', estimated_on='2026-09-08T08:40:00Z'))
        self.assertEqual(mapped['estimatedOff'], '2026-09-08T01:27:00Z')
        self.assertEqual(mapped['estimatedOn'], '2026-09-08T08:40:00Z')
        self.assertNotIn('estimatedOff', f.normalized(self.row()))
    def test_cache_secret_and_exact_day(self):
        with patch.dict(os.environ, {'FLIGHTAWARE_API_KEY':'test-secret'}), patch.object(f,'request_json', return_value={'flights':[self.row(),self.row(scheduled_out='2020-01-01T12:00:00Z')]}) as request:
            a=f.status(' BA 178 ',self.day.isoformat()); b=f.status('BA178',self.day.isoformat())
            self.assertEqual(len(a['flights']),1);self.assertEqual(a['fetchedAt'],b['fetchedAt']);self.assertEqual(request.call_count,1)
            self.assertNotIn('test-secret',request.call_args.args[0]);self.assertNotIn('test-secret',str(a))
            self.assertIn('max_pages=1',request.call_args.args[0])
    def test_history_entitlement_and_sample(self):
        with patch.dict(os.environ, {'FLIGHTAWARE_API_KEY':'test','FLIGHTAWARE_HISTORY_ENABLED':'false'}):
            with self.assertRaises(ProviderError):f.history('BA178',self.day.isoformat())
        row=self.row(scheduled_out=(self.day-dt.timedelta(days=2)).isoformat()+'T22:00:00Z',actual_in=self.day.isoformat()+'T05:00:00Z')
        with patch.dict(os.environ, {'FLIGHTAWARE_API_KEY':'test','FLIGHTAWARE_HISTORY_ENABLED':'true'}), patch.object(f,'request_json',return_value={'flights':[row,self.row()]}):
            self.assertEqual(len(f.history('BA178',self.day.isoformat())['flights']),1)
    def test_position_validation(self):
        with patch.dict(os.environ, {'FLIGHTAWARE_API_KEY':'test'}), patch.object(f,'request_json',return_value={'last_position':{'latitude':40,'longitude':-60,'timestamp':'2026-09-06T10:00:00Z','altitude':350,'groundspeed':470}}):
            self.assertEqual(f.position('BAW178-test-1')['altitude'],350)
        with self.assertRaises(ProviderError):f.position('../anything')
    def test_future_dates_do_not_charge_provider(self):
        with patch.object(f,'fetch') as fetch:
            result=f.status('BA178',(self.day+dt.timedelta(days=30)).isoformat());self.assertEqual(result['flights'],[]);fetch.assert_not_called()

if __name__=='__main__':unittest.main()
