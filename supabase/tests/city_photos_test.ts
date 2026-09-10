import assert from 'node:assert/strict';
import { cityPhoto, cityPhotoQuery, commonsURL, cityLandmark } from '../functions/travel-api/city-photos.ts';

function page(overrides: any = {}) {
  return { index: 1, title: 'File:20101024 Acropolis panoramic view from Areopagus hill Athens Greece.jpg', imageinfo: [{
    width: 1200, height: 800, mime: 'image/jpeg', thumburl: 'https://thumb.wikimedia.org/athens.jpg',
    descriptionurl: 'https://commons.wikimedia.org/wiki/File:Athens_skyline.jpg',
    extmetadata: { Artist: { value: '<a href="/user">Alex &amp; Sam</a>' },
      LicenseShortName: { value: 'CC BY-SA 4.0' }, LicenseUrl: { value: 'https://creativecommons.org/licenses/by-sa/4.0' },
      Credit: { value: 'Own work' } }, ...overrides,
  }] };
}
Deno.test('city-photo input and image hosts reject malformed or untrusted data', () => {
  assert.equal(cityPhotoQuery('  Athens, Greece  '), 'Athens, Greece');
  for (const value of ['', 'a', 'x'.repeat(201), 'Paris\nFrance']) assert.throws(() => cityPhotoQuery(value));
  assert.equal(commonsURL('//upload.wikimedia.org/place', 'upload.wikimedia.org'), 'https://upload.wikimedia.org/place');
  for (const value of ['http://upload.wikimedia.org/x', 'https://upload.wikimedia.org.evil.test/x', 'https://evil.test/x', 'https://key@upload.wikimedia.org/x']) assert.equal(commonsURL(value, 'upload.wikimedia.org'), undefined);
});
Deno.test('city photo uses exactly one free provider lookup including image URL and permanent-copy credits', async () => {
  const original = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = ((input: string | URL | Request) => {
    calls++; const url = new URL(String(input));
    assert.equal(url.host, 'commons.wikimedia.org');
    assert.equal(url.searchParams.get('generator'), null);
    assert.equal(url.searchParams.get('titles'), 'File:20101024 Acropolis panoramic view from Areopagus hill Athens Greece.jpg');
    assert.equal(url.searchParams.get('iiprop'), 'url|size|mime|extmetadata');
    return Promise.resolve(Response.json({ query: { pages: [page()] } }));
  }) as typeof fetch;
  try {
    const result = await cityPhoto('Athens, Greece');
    assert.equal(calls, 1); assert.equal(result.photo?.authors[0].name, 'Alex & Sam');
    assert.equal(result.photo?.license, 'CC BY-SA 4.0');
    assert.equal(result.photo?.attribution, 'Own work');
    assert.equal(result.photo?.imageURL, 'https://thumb.wikimedia.org/athens.jpg');
  } finally { globalThis.fetch = original; }
});
Deno.test('unusable photos do not trigger another search or a different provider', async () => {
  const original = globalThis.fetch;
  try {
    for (const pages of [[], [page({ width: 400 })], [page({ extmetadata: {} })], [page({ thumburl: 'https://evil.test/x' })]]) {
      let count = 0;
      globalThis.fetch = (() => { count++; return Promise.resolve(Response.json({ query: { pages } })); }) as typeof fetch;
      assert.deepEqual(await cityPhoto('Paris, France'), { photo: null }); assert.equal(count, 1);
    }
    let count = 0;
    globalThis.fetch = (() => { count++; return Promise.resolve(new Response('', { status: 503 })); }) as typeof fetch;
    await assert.rejects(() => cityPhoto('Paris, France')); assert.equal(count, 1);
  } finally { globalThis.fetch = original; }
});
Deno.test('guest route advertises availability and enforces rate limits before the single provider lookup', async () => {
  Deno.env.set('SUPABASE_URL', 'https://city-photo.test');
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'test-service-key');
  const { handler } = await import('../functions/travel-api/index.ts');
  const original = globalThis.fetch;
  let exhausted = false, photoCalls = 0;
  globalThis.fetch = ((url: string | URL | Request, init?: RequestInit) => {
    if (String(url).includes('/rpc/travel_limit')) {
      const body = JSON.parse(String(init?.body));
      return Promise.resolve(Response.json(!(exhausted && body.k === 'city-photo-global')));
    }
    assert.ok(String(url).startsWith('https://commons.wikimedia.org/')); photoCalls++;
    return Promise.resolve(Response.json({ query: { pages: [] } }));
  }) as typeof fetch;
  try {
    const status = await handler(new Request('https://edge.test/travel-api/v1/status'));
    assert.equal((await status.json()).cityPhotos, true);
    const request = () => new Request('https://edge.test/travel-api/v1/cities/photo?city=Athens%2C%20Greece');
    const result = await handler(request()); assert.equal(result.status, 200);
    assert.equal(result.headers.get('cache-control'), 'no-store'); assert.deepEqual(await result.json(), { photo: null });
    assert.equal(photoCalls, 1);
    exhausted = true;
    assert.equal((await handler(request())).status, 429); assert.equal(photoCalls, 1);
    assert.equal((await handler(new Request('https://edge.test/travel-api/v1/cities/photo?city=x'))).status, 400);
  } finally { globalThis.fetch = original; }
});

Deno.test('catalog cities use defining landmarks and disambiguate countries', () => {
  for (const [city, subject] of [['Paris, France', 'Eiffel Tower'], ['London, UK', 'Big Ben'], ['Athens, Greece', 'Acropolis'],
    ['Tokyo', 'Tokyo Tower'], ['Bangkok', 'Wat Arun'], ['New York City, USA', 'Statue of Liberty'], ['Singapore', 'Marina Bay Sands'],
    ['Hong Kong', 'Victoria Harbour'], ['Dubai', 'Burj Khalifa'], ['Shanghai', 'Oriental Pearl Tower'], ['Istanbul, Turkey', 'Hagia Sophia'],
    ['Macao', "Ruins of Saint Paul's"], ['Kuala Lumpur', 'Petronas Towers']]) assert.equal(cityLandmark(city)?.subject, subject);
  assert.equal(cityLandmark('Paris, Texas'), undefined);
  assert.equal(cityLandmark('London, Canada'), undefined);
});
Deno.test('Paris requests the curated Eiffel Tower file in one call; unrelated and replica photos are rejected', async () => {
  const original = globalThis.fetch;
  try {
    let calls = 0;
    globalThis.fetch = ((input: string | URL | Request) => {
      calls++; const url = new URL(String(input));
      assert.equal(url.searchParams.get('titles'), 'File:Eiffel tower from trocadero.jpg');
      assert.equal(url.searchParams.get('generator'), null);
      const photo = page(); photo.title = 'File:Eiffel tower from trocadero.jpg';
      return Promise.resolve(Response.json({ query: { pages: [photo] } }));
    }) as typeof fetch;
    assert.ok((await cityPhoto('Paris, France')).photo); assert.equal(calls, 1);
    for (const title of ['File:Athens hotel.jpg', 'File:Acropolis miniature.jpg']) {
      calls = 0;
      globalThis.fetch = (() => { calls++; const photo = page(); photo.title = title; return Promise.resolve(Response.json({ query: { pages: [photo] } })); }) as typeof fetch;
      assert.deepEqual(await cityPhoto('Athens, Greece'), { photo: null }); assert.equal(calls, 1);
    }
  } finally { globalThis.fetch = original; }
});

Deno.test('regional New York names request only the selected Liberty photograph', async () => {
  const original = globalThis.fetch;
  try {
    for (const city of ['New York, NY, United States', 'New York City, NY', 'NYC, USA']) {
      let calls = 0;
      globalThis.fetch = ((input: string | URL | Request) => {
        calls++; const url = new URL(String(input));
        assert.equal(url.searchParams.get('titles'), 'File:Statue of Liberty, NY.jpg');
        assert.equal(url.searchParams.get('gsrsearch'), null);
        const selected = page(); selected.title = 'File:Statue of Liberty, NY.jpg';
        const plaque = page(); plaque.title = 'File:New York Yacht Club plaque.jpg';
        return Promise.resolve(Response.json({query: {pages: [plaque, selected]}}));
      }) as typeof fetch;
      assert.equal((await cityPhoto(city)).photo?.title, 'Statue of Liberty, NY.jpg');
      assert.equal(calls, 1);
    }
    assert.equal(cityLandmark('Paris, Texas, United States'), undefined);
    assert.equal(cityLandmark('London, Ontario, Canada'), undefined);
  } finally { globalThis.fetch = original; }
});
