import assert from 'node:assert/strict';
Deno.env.set('SUPABASE_URL', 'https://pexels-photo.test');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'test-key');
const { pexelsDestination, pexelsURL, selectPexelsPhoto, pexelsCityPhoto, isDaytimePexelsPhoto } = await import('../functions/travel-api/pexels-city-photos.ts');
const photo = (alt = 'Eiffel Tower above the Paris skyline in daylight', id = 1) => ({ id, alt, width: 4000, height: 2250,
  src: { original: `https://images.pexels.com/photos/${id}/photo.jpeg` }, url: `https://www.pexels.com/photo/paris-${id}/`,
  photographer: 'Test photographer', photographer_url: 'https://www.pexels.com/@photographer' });
Deno.test('Pexels targets defining landmarks and respects city country disambiguation', () => {
  assert.match(pexelsDestination('Paris, France').query, /Eiffel Tower/);
  assert.match(pexelsDestination('New York, NY, United States').query, /Statue of Liberty/);
  assert.match(pexelsDestination('Tokyo, Japan').query, /Tokyo Tower/);
  assert.match(pexelsDestination('Rome, Italy').query, /Colosseum/);
  assert.doesNotMatch(pexelsDestination('Paris, Texas, United States').query, /Eiffel/);
  assert.doesNotMatch(pexelsDestination('London, Ontario, Canada').query, /Big Ben/);
});
Deno.test('Pexels ranks recognizable scenic landscape photos and produces an exact 16:9 rendition', () => {
  const result = selectPexelsPhoto([photo('Eiffel Tower in daylight', 1), photo('Paris Eiffel Tower skyline in daylight', 2)], 'Paris');
  assert.equal(result?.sourceURL, 'https://www.pexels.com/photo/paris-2/');
  const url = new URL(result!.imageURL);
  assert.equal(url.searchParams.get('w'), '1200'); assert.equal(url.searchParams.get('h'), '675');
  assert.equal(result?.authors[0].name, 'Test photographer'); assert.equal(result?.provider, 'pexels');
});
Deno.test('Pexels refuses plaques, replicas, unrelated scenes, portraits and unsafe hosts', () => {
  for (const p of [photo('Eiffel Tower plaque'), photo('Eiffel Tower replica in Las Vegas'), photo('New York yacht club'),
    {...photo(), width: 900, height: 1600}, {...photo(), width: 600}, {...photo(), src: { original: 'https://evil.test/photo.jpeg' }},
    {...photo(), photographer_url: 'https://evil.test/author'}, photo('Generic city skyline')]) {
    assert.equal(selectPexelsPhoto([p], 'Paris'), null);
  }
  for (const url of ['http://images.pexels.com/a', 'https://images.pexels.com.evil.test/a', 'https://key@images.pexels.com/a',
    'https://images.pexels.com:8443/a']) assert.equal(pexelsURL(url, true), undefined);
});
Deno.test('Pexels cache reuses one authenticated search across trips and concurrent callers', async () => {
  Deno.env.set('PEXELS_API_KEY', 'fixture-pexels-secret');
  const original = fetch; let searches = 0, quota = 0; const cache = new Map<string, unknown>();
  globalThis.fetch = (async (input, init) => {
    const url = String(input);
    if (url.includes('/travel_provider_cache')) {
      if (init?.method === 'POST') { const body = JSON.parse(String(init.body)); cache.set(body.key, body.value); return Response.json(null); }
      const key = new URL(url).searchParams.get('key')!.slice(3);
      return Response.json(cache.has(key) ? [{value: cache.get(key)}] : []);
    }
    if (url.includes('/rpc/travel_limit')) { quota++; return Response.json(true); }
    searches++;
    assert.equal(new Headers(init?.headers).get('Authorization'), 'fixture-pexels-secret');
    assert.equal(new URL(url).hostname, 'api.pexels.com'); assert.ok(!url.includes('fixture-pexels-secret'));
    assert.equal(new URL(url).searchParams.get('orientation'), 'landscape');
    assert.equal(new URL(url).searchParams.get('per_page'), '30');
    return Response.json({photos: [photo()]});
  }) as typeof fetch;
  try {
    const [a,b] = await Promise.all([pexelsCityPhoto('Paris, France'), pexelsCityPhoto('Paris, France')]);
    assert.deepEqual(a,b); assert.equal(a.photo?.provider, 'pexels');
    assert.deepEqual(await pexelsCityPhoto('PARIS, FR'),a);
    assert.equal(searches,1); assert.equal(quota,2);
    assert.ok(!JSON.stringify(a).includes('fixture-pexels-secret'));
  } finally { globalThis.fetch = original; Deno.env.delete('PEXELS_API_KEY'); }
});
Deno.test('Pexels missing configuration and exhausted quota never invoke the provider', async () => {
  const original = fetch; let searches = 0;
  globalThis.fetch = ((input) => {
    if (String(input).includes('travel_provider_cache')) return Promise.resolve(Response.json([]));
    if (String(input).includes('/rpc/travel_limit')) return Promise.resolve(Response.json(false));
    searches++; return Promise.resolve(Response.json({photos: []}));
  }) as typeof fetch;
  try {
    Deno.env.delete('PEXELS_API_KEY'); await assert.rejects(() => pexelsCityPhoto('Paris'));
    Deno.env.set('PEXELS_API_KEY', 'fixture'); await assert.rejects(() => pexelsCityPhoto('Tokyo'));
    assert.equal(searches,0);
  } finally { globalThis.fetch = original; Deno.env.delete('PEXELS_API_KEY'); }
});
Deno.test('Pexels route is guest accessible, advertises configuration and rejects malformed queries', async () => {
  const { handler } = await import('../functions/travel-api/index.ts');
  Deno.env.set('PEXELS_API_KEY', 'fixture'); const original = fetch;
  globalThis.fetch = ((input) => {
    if (String(input).includes('/rpc/travel_limit')) return Promise.resolve(Response.json(true));
    if (String(input).includes('travel_provider_cache')) return Promise.resolve(Response.json([{value: {photo: null}}]));
    throw new Error('Cached route must not call provider');
  }) as typeof fetch;
  try {
    assert.equal((await (await handler(new Request('https://edge.test/travel-api/v1/status'))).json()).pexelsCityPhotos, true);
    const response = await handler(new Request('https://edge.test/travel-api/v1/cities/pexels-photo?city=Paris'));
    assert.equal(response.status,200); assert.equal(response.headers.get('cache-control'),'no-store');
    assert.deepEqual(await response.json(),{photo: null});
    assert.equal((await handler(new Request('https://edge.test/travel-api/v1/cities/pexels-photo?city=x'))).status,400);
    Deno.env.delete('PEXELS_API_KEY');
    assert.equal((await handler(new Request('https://edge.test/travel-api/v1/cities/pexels-photo?city=Paris'))).status,503);
  } finally { globalThis.fetch = original; Deno.env.delete('PEXELS_API_KEY'); }
});

Deno.test('Every Pexels cover must have affirmative daytime metadata and no night or twilight signals', () => {
  for (const alt of ['Tokyo Tower at night', 'Tokyo Tower illuminated in a night cityscape',
    'Tokyo Tower at sunset', 'Tokyo Tower in morning twilight', 'Tokyo Tower in golden hour',
    'Tokyo Tower in the city skyline', 'Tokyo Tower under blue skies at dusk']) {
    assert.equal(isDaytimePexelsPhoto(photo(alt)), false, alt);
    assert.equal(selectPexelsPhoto([photo(alt)], 'Tokyo, Japan'), null, alt);
  }
  for (const alt of ['Tokyo Tower in daylight', 'Tokyo Tower under a clear blue sky', 'Sunny afternoon in Tokyo with Tokyo Tower']) {
    assert.equal(isDaytimePexelsPhoto(photo(alt)), true, alt);
    assert.equal(selectPexelsPhoto([photo(alt)], 'Tokyo, Japan')?.provider, 'pexels');
  }
  assert.equal(isDaytimePexelsPhoto({...photo('Tokyo Tower in daylight'), url: 'https://www.pexels.com/photo/tokyo-night-123/'}), false);
  assert.match(pexelsDestination('Tokyo, Japan').query, /daytime$/);
  assert.match(pexelsDestination('Burlington, Vermont, United States').query, /daytime$/);
});
