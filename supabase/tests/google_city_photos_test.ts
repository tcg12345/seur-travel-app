import assert from 'node:assert/strict';
import { googleCityPhoto, googlePhotoURL } from '../functions/travel-api/google-city-photos.ts';

const place = (name = 'Statue of Liberty') => ({ id: 'place_id', displayName: { text: name },
  googleMapsUri: 'https://maps.google.com/?cid=123', photos: [
    { name: 'places/place_id/photos/undersized', widthPx: 300, heightPx: 200 },
    { name: 'places/place_id/photos/portrait', widthPx: 900, heightPx: 1600,
      googleMapsUri: 'https://www.google.com/maps/photo/123', authorAttributions: [
        { displayName: 'Photographer', uri: 'https://www.google.com/maps/contrib/123', photoUri: 'https://lh3.googleusercontent.com/avatar' }] },
  ] });
Deno.test('Google photos target the defining landmark with exactly one search and one media call', async () => {
  Deno.env.set('GOOGLE_PLACES_API_KEY', 'fixture-secret');
  const original = fetch; let calls = 0;
  globalThis.fetch = ((input, init) => {
    calls++; const url = String(input);
    assert.equal(new Headers(init?.headers).get('X-Goog-Api-Key'), 'fixture-secret');
    assert.ok(!url.includes('fixture-secret'));
    if (calls === 1) {
      assert.equal(url, 'https://places.googleapis.com/v1/places:searchText');
      const body = JSON.parse(String(init?.body));
      assert.equal(body.textQuery, 'Statue of Liberty, New York, United States');
      assert.equal(body.pageSize, 1);
      return Promise.resolve(Response.json({ places: [place()] }));
    }
    assert.equal(url, 'https://places.googleapis.com/v1/places/place_id/photos/portrait/media?maxWidthPx=1000&skipHttpRedirect=true');
    return Promise.resolve(Response.json({ photoUri: 'https://lh3.googleusercontent.com/photo' }));
  }) as typeof fetch;
  try {
    const result = await googleCityPhoto('New York, NY, United States');
    assert.equal(calls, 2); assert.equal(result.photo?.provider, 'google');
    assert.equal(result.photo?.attribution, 'Google Maps');
    assert.equal(result.photo?.sourceURL, 'https://www.google.com/maps/photo/123');
    assert.equal(result.photo?.authors[0].name, 'Photographer');
    assert.equal(result.photo?.authors[0].avatarURL, 'https://lh3.googleusercontent.com/avatar');
    assert.ok(!JSON.stringify(result).includes('fixture-secret'));
    assert.ok(!JSON.stringify(result).includes('places/place_id/photos/'));
  } finally { globalThis.fetch = original; }
});
Deno.test('Google photos reject unrelated places and unsafe resources without retries', async () => {
  Deno.env.set('GOOGLE_PLACES_API_KEY', 'fixture-secret'); const original = fetch;
  try {
    for (const places of [[], [place('New York Yacht Club')], [{ ...place(), photos: [] }],
      [{ ...place(), photos: [{ name: 'places/other/photos/x', widthPx: 1000, heightPx: 800 }] }]]) {
      let calls = 0; globalThis.fetch = (() => { calls++; return Promise.resolve(Response.json({ places })); }) as typeof fetch;
      assert.deepEqual(await googleCityPhoto('New York'), { photo: null }); assert.equal(calls, 1);
    }
    let calls = 0; globalThis.fetch = (() => { calls++; return Promise.resolve(new Response('secret provider body', {status: 500})); }) as typeof fetch;
    await assert.rejects(() => googleCityPhoto('Paris'), e => !String(e).includes('secret provider body'));
    assert.equal(calls, 1);
  } finally { globalThis.fetch = original; }
});
Deno.test('Google photo URLs require trusted HTTPS origins', () => {
  for (const u of ['http://lh3.googleusercontent.com/a', 'https://lh3.googleusercontent.com.evil.test/a',
    'https://key@lh3.googleusercontent.com/a', 'https://lh3.googleusercontent.com:8443/a', 'https://evil.test/a']) {
    assert.equal(googlePhotoURL(u, true), undefined);
  }
  assert.equal(googlePhotoURL('https://www.google.com/maps/x'), 'https://www.google.com/maps/x');
  assert.equal(googlePhotoURL('https://evil.test/x'), undefined);
});
Deno.test('Google route is guest accessible, no-store and globally bounded before paid calls', async () => {
  Deno.env.set('SUPABASE_URL', 'https://google-photo.test'); Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'test-key');
  Deno.env.set('GOOGLE_PLACES_API_KEY', 'fixture-secret');
  const { handler } = await import('../functions/travel-api/index.ts');
  const original = fetch; let exhausted = false, calls = 0;
  globalThis.fetch = ((input, init) => {
    if (String(input).includes('/rpc/travel_limit')) {
      const body = JSON.parse(String(init?.body));
      if (body.k === 'google-city-photo-global') { assert.equal(body.maximum, 500); }
      return Promise.resolve(Response.json(!exhausted));
    }
    calls++; return Promise.resolve(Response.json({ places: [] }));
  }) as typeof fetch;
  try {
    assert.equal((await (await handler(new Request('https://edge.test/travel-api/v1/status'))).json()).googleCityPhotos, true);
    const req = () => new Request('https://edge.test/travel-api/v1/cities/google-photo?city=Paris');
    const response = await handler(req()); assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store'); assert.equal(calls, 1);
    exhausted = true; assert.equal((await handler(req())).status, 429); assert.equal(calls, 1);
    exhausted = false;
    assert.equal((await handler(new Request('https://edge.test/travel-api/v1/cities/google-photo?city=x'))).status, 400);
  } finally { globalThis.fetch = original; }
});
