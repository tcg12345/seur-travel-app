import assert from 'node:assert/strict';
Deno.env.set('SUPABASE_URL', 'https://budget.test');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'test-service-key');
const { exchangeRates } = await import('../functions/travel-api/exchange-rates.ts');
const { handler } = await import('../functions/travel-api/index.ts');
const { validateDocument } = await import('../functions/travel-api/validation.ts');
const { sanitizedTemplate } = await import('../functions/travel-api/templates.ts');
const seed = JSON.parse(await Deno.readTextFile(new URL('../../iOS/Aurum/Resources/TripTemplates.json', import.meta.url)))[0];
const a = '00000000-0000-4000-8000-000000000001', b = '00000000-0000-4000-8000-000000000002';
function ledger() {
  const d = structuredClone(seed);
  d.budgetTarget = 1200; d.homeCurrency = 'USD'; d.companions = [{ id: a, name: 'Alex' }, { id: b, name: 'Blair' }];
  d.events[0].isDone = true; d.events[0].cost = { amount: 100.25, currency: 'EUR', paidBy: a, splitBetween: [a, b] };
  d.hotels[0].cost = { amount: 200, currency: 'USD', paidBy: b, splitBetween: [a, b], isPaid: true };
  return d;
}
Deno.test('budget, completion and split metadata round trip without changing legacy documents', () => {
  validateDocument(seed);
  const d = ledger(), before = JSON.stringify(d); validateDocument(d); assert.equal(JSON.stringify(d), before);
});
Deno.test('reject invalid budgets, completion flags, duplicate people and dangling cost splits', () => {
  for (const mutate of [
    (d: any) => d.budgetTarget = -1,
    (d: any) => d.budgetTarget = Infinity,
    (d: any) => d.homeCurrency = 'BAD',
    (d: any) => d.events[0].isDone = 'yes',
    (d: any) => d.hotels[0].cost.isPaid = 1,
    (d: any) => d.companions.push(d.companions[0]),
    (d: any) => d.events[0].cost.splitBetween = [],
    (d: any) => d.events[0].cost.splitBetween = [a, a],
    (d: any) => d.events[0].cost.paidBy = crypto.randomUUID(),
    (d: any) => d.events[0].cost.splitBetween = [crypto.randomUUID()],
  ]) { const d = ledger(); mutate(d); assert.throws(() => validateDocument(d)); }
});
Deno.test('shared templates retain estimates but remove all personal ledger fields', () => {
  const d = ledger(); d.templateMeta.includesCosts = true;
  const clean = sanitizedTemplate(d, 'editor');
  assert.equal(clean.events[0].cost.amount, 100.25);
  for (const key of ['budgetTarget', 'homeCurrency', 'companions', 'paidBy', 'splitBetween', 'isDone', 'isPaid']) assert.equal(JSON.stringify(clean).includes('"' + key + '"'), false);
});
const now = Date.parse('2026-09-08T18:00:00Z');
const validRate = [{ date: '2026-09-08', base: 'USD', quote: 'EUR', rate: 0.8 }];
const cached = (age = 0) => ({ base: 'USD', rates: { USD: 1, EUR: 0.8 }, dates: { USD: '2026-09-08', EUR: '2026-09-07' }, fetchedAt: (now - age * 86400000) / 1000, stale: false });
async function mock(initial: any, provider: () => Response, run: (stats: { upstream: number; writes: number }) => Promise<void>) {
  const original = globalThis.fetch, stats = { upstream: 0, writes: 0 }; let value = initial;
  globalThis.fetch = async (input, options) => {
    const url = new URL(String(input));
    if (url.origin === 'https://api.frankfurter.dev') { stats.upstream++; assert.equal(url.searchParams.get('base'), 'USD'); return provider(); }
    assert.equal(url.origin, 'https://budget.test', 'No real network');
    if (url.pathname === '/rest/v1/travel_provider_cache') {
      if (options?.method === 'POST') { stats.writes++; value = JSON.parse(String(options.body)).value; return Response.json({}); }
      return Response.json(value ? [{ value }] : []);
    }
    if (url.pathname === '/rest/v1/rpc/travel_limit') return Response.json(true);
    if (url.pathname === '/rest/v1/travel_sessions') return Response.json([{ user_id: a }]);
    throw new Error('Unexpected request: ' + url.pathname);
  };
  try { await run(stats); } finally { globalThis.fetch = original; }
}
Deno.test('daily rates use persistent cache and coalesce simultaneous misses', async () => {
  await mock(cached(), () => { throw new Error('Cache hit must not fetch'); }, async stats => {
    const result = await exchangeRates(now); assert.equal(result.stale, false); assert.equal(stats.upstream, 0);
  });
  await mock(undefined, () => Response.json(validRate), async stats => {
    const results = await Promise.all([exchangeRates(now), exchangeRates(now), exchangeRates(now)]);
    assert.equal(stats.upstream, 1); assert.equal(stats.writes, 1); assert.deepEqual(results[0].rates, { USD: 1, EUR: 0.8 });
    await exchangeRates(now); assert.equal(stats.upstream, 1);
  });
});
Deno.test('failed refresh explicitly marks cached rates stale and rejects expired rates', async () => {
  await mock(cached(1), () => Response.json({}, { status: 503 }), async () => { assert.equal((await exchangeRates(now)).stale, true); });
  await mock(cached(9), () => Response.json({}, { status: 503 }), async () => { await assert.rejects(() => exchangeRates(now), /temporarily unavailable/); });
});
Deno.test('invalid rates never populate the cache', async () => {
  for (const value of [0, -1, '0.8', null]) {
    await mock(undefined, () => Response.json([{ ...validRate[0], rate: value }]), async stats => {
      await assert.rejects(() => exchangeRates(now)); assert.equal(stats.writes, 0);
    });
  }
});
Deno.test('exchange-rate endpoint requires a Seur session', async () => {
  await mock(undefined, () => Response.json(validRate), async stats => {
    const response = await handler(new Request('https://budget.test/functions/v1/travel-api/v1/exchange-rates'));
    assert.equal(response.status, 401); assert.equal(stats.upstream, 0);
  });
});
