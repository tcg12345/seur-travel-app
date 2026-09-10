import { platform, limit } from './platform.ts';
import { day, finite, Problem, requireValue } from './validation.ts';
const currencies = ['USD','EUR','GBP','JPY','THB','SGD','HKD','AED','CNY','TRY','MYR','AUD','CAD','CHF'];
const key = 'fx-daily-v1-USD';
type Rates = { base: string; rates: Record<string, number>; dates: Record<string, string>; fetchedAt: number; stale: boolean };
let pending: Promise<Rates> | undefined;
function valid(value: any, now: number): value is Rates {
  return value?.base === 'USD' && value.rates?.USD === 1 && finite(value.fetchedAt) &&
    value.fetchedAt <= now / 1000 + 60 && value.fetchedAt >= now / 1000 - 7 * 86400 &&
    value.dates && Object.entries(value.rates).every(([currency, rate]) => currencies.includes(currency) && finite(rate) && (rate as number) > 0 && day(value.dates[currency]));
}
export async function exchangeRates(now = Date.now()): Promise<Rates> {
  if (pending) return await pending;
  const task = (async () => {
    const rows = await platform('/rest/v1/travel_provider_cache?select=value&key=eq.' + key);
    const cached: Rates | undefined = valid(rows?.[0]?.value, now) ? rows[0].value : undefined;
    const today = new Date(now).toISOString().slice(0, 10);
    if (cached && new Date(cached.fetchedAt * 1000).toISOString().slice(0, 10) === today) return { ...cached, stale: false };
    try {
      await limit('fx-provider-global', 100, 3600);
      const response = await fetch('https://api.frankfurter.dev/v2/rates?base=USD&quotes=' + currencies.join(','), { signal: AbortSignal.timeout(8000) });
      requireValue(response.ok, 'Exchange rates are temporarily unavailable.', 503);
      const data = await response.json();
      requireValue(Array.isArray(data) && data.length > 0 && data.length <= 100, 'Invalid exchange rate response.', 503);
      const value: Rates = { base: 'USD', rates: { USD: 1 }, dates: { USD: today }, fetchedAt: now / 1000, stale: false };
      for (const row of data) {
        requireValue(row.base === 'USD' && currencies.includes(row.quote) && finite(row.rate) && row.rate > 0 &&
          day(row.date) && row.date <= today && Date.parse(row.date) >= now - 8 * 86400000,
          'Invalid exchange rate response.', 503);
        if (row.quote !== 'USD') { value.rates[row.quote] = row.rate; value.dates[row.quote] = row.date; }
      }
      requireValue(Object.keys(value.rates).length > 1, 'Exchange rates are temporarily unavailable.', 503);
      await platform('/rest/v1/travel_provider_cache', 'POST', { key, value, expires: new Date(now + 8 * 86400000).toISOString() }, { Prefer: 'resolution=merge-duplicates' });
      return value;
    } catch {
      if (cached) return { ...cached, stale: true };
      throw new Problem('Exchange rates are temporarily unavailable. Original amounts are still available.', 503);
    }
  })();
  pending = task;
  try { return await task; } finally { pending = undefined; }
}
