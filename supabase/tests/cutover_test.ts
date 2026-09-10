import assert from 'node:assert/strict';
Deno.env.set('SUPABASE_URL', 'https://cutover.test');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'server-test-key');
const { handler } = await import('../functions/travel-api/index.ts');
const actor = '00000000-0000-4000-8000-000000000001';
const journey = '00000000-0000-4000-8000-000000000002';
const bearer = 'a'.repeat(80);
const photoPath = `${actor}/${journey}/version/photo.jpg`;
const bytes = new Uint8Array([255, 216, 255, 217]);
const remote = () => ({ id: journey, owner: { id: actor, handle: 'owner', name: 'Owner' },
  revision: 1, document: { id: journey, places: [{ photos: [{ id: 'photo-id', storagePath: photoPath }] }] } });
type Call = { path: string; method: string; body: any };
async function mock(respond: (call: Call) => Response | undefined, run: (calls: Call[]) => Promise<void>) {
  const original = globalThis.fetch, calls: Call[] = [];
  globalThis.fetch = async (input, init) => {
    const url = new URL(String(input));
    assert.equal(url.origin, 'https://cutover.test', 'No live network allowed');
    const call = { path: url.pathname, method: init?.method ?? 'GET', body: init?.body ? JSON.parse(String(init.body)) : undefined };
    calls.push(call);
    const response = respond(call);
    if (response) return response;
    if (call.path === '/rest/v1/rpc/travel_limit') return Response.json(true);
    if (call.path === '/rest/v1/travel_sessions') return Response.json([{ user_id: actor }]);
    throw new Error('Unexpected request: ' + call.method + ' ' + call.path);
  };
  try { await run(calls); } finally { globalThis.fetch = original; }
}
function request(path: string, method = 'GET', body?: unknown, authenticated = true) {
  return handler(new Request('https://cutover.test/functions/v1/travel-api' + path, {
    method, headers: { ...(authenticated ? { Authorization: 'Bearer ' + bearer } : {}), 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  }));
}
Deno.test('cloud and feed summaries omit storage paths; detail retains photo IDs and bytes', async () => {
  await mock(call => {
    if (call.path === '/rest/v1/rpc/travel_dispatch') return Response.json(call.body.path === '/v1/documents' ? [remote()] : remote());
    if (call.path === '/rest/v1/rpc/travel_social_feed') return Response.json([remote()]);
    if (call.path === '/storage/v1/object/authenticated/journey-photos/' + photoPath) return new Response(bytes);
  }, async calls => {
    for (const path of ['/v1/documents', '/v1/feed']) {
      const response = await request(path); assert.equal(response.status, 200);
      const [summary] = await response.json();
      assert.equal(summary.isSummary, true); assert.deepEqual(summary.document.places[0].photos, []);
      assert.equal(JSON.stringify(summary).includes('storagePath'), false);
    }
    assert.equal(calls.some(c => c.path.startsWith('/storage/')), false);
    const response = await request('/v1/documents/' + journey); assert.equal(response.status, 200);
    const full = await response.json();
    assert.notEqual(full.isSummary, true);
    assert.deepEqual(full.document.places[0].photos, [{ id: 'photo-id', jpeg: '/9j/2Q==' }]);
  });
});
Deno.test('revoked detail access never reads photos; missing photos fail instead of silently truncating', async () => {
  for (const revoked of [true, false]) {
    await mock(call => {
      if (call.path === '/rest/v1/rpc/travel_dispatch') return revoked
        ? Response.json({ code: 'PT403', message: 'Access revoked.' }, { status: 403 }) : Response.json(remote());
      if (call.path.startsWith('/storage/')) return Response.json({}, { status: 404 });
    }, async calls => {
      const response = await request('/v1/documents/' + journey);
      assert.equal(response.status, revoked ? 403 : 502);
      if (revoked) assert.equal(calls.some(c => c.path.startsWith('/storage/')), false);
    });
  }
});
Deno.test('account deletion pages through owner folders and abandoned versions before deleting Auth', async () => {
  const removed: string[] = [];
  await mock(call => {
    if (call.path === '/storage/v1/object/list/journey-photos') {
      const { prefix, offset, limit } = call.body; assert.equal(limit, 100);
      if (prefix === actor) return Response.json([{ name: journey, id: null }]);
      if (prefix === `${actor}/${journey}`) return Response.json([{ name: 'abandoned', id: null }]);
      assert.equal(prefix, `${actor}/${journey}/abandoned`);
      return Response.json(Array.from({ length: 205 }, (_, i) => ({ name: `${i}.jpg`, id: String(i) })).slice(offset, offset + limit));
    }
    if (call.path === '/storage/v1/object/journey-photos') {
      assert.equal(call.method, 'DELETE'); assert.ok(call.body.prefixes.length <= 100);
      removed.push(...call.body.prefixes); return Response.json([]);
    }
    if (call.path === '/auth/v1/admin/users/' + actor) {
      assert.equal(call.method, 'DELETE'); assert.equal(new Set(removed).size, 205); return Response.json({});
    }
  }, async calls => {
    const response = await request('/v1/account', 'DELETE', { user_id: 'someone-else' });
    assert.equal(response.status, 200); assert.deepEqual(await response.json(), { ok: true });
    assert.equal(calls.at(-1)?.path, '/auth/v1/admin/users/' + actor);
    assert.ok(removed.every(key => key.startsWith(actor + '/')));
  });
});
Deno.test('storage failure retains the Auth account and a retry can finish deletion', async () => {
  let fail = true, deleted = false;
  await mock(call => {
    if (call.path === '/storage/v1/object/list/journey-photos') return Response.json([{ name: 'orphan.jpg', id: 'object' }]);
    if (call.path === '/storage/v1/object/journey-photos') return Response.json({}, { status: fail ? 503 : 200 });
    if (call.path === '/auth/v1/admin/users/' + actor) { deleted = true; return Response.json({}); }
  }, async () => {
    assert.equal((await request('/v1/account', 'DELETE')).status, 502); assert.equal(deleted, false);
    fail = false;
    assert.equal((await request('/v1/account', 'DELETE')).status, 200); assert.equal(deleted, true);
  });
});
Deno.test('listing and Auth failures are surfaced; unauthenticated deletion never reaches storage', async () => {
  for (const failing of ['list', 'auth']) {
    await mock(call => {
      if (call.path === '/storage/v1/object/list/journey-photos') return Response.json([], { status: failing === 'list' ? 503 : 200 });
      if (call.path === '/auth/v1/admin/users/' + actor) return Response.json({}, { status: 500 });
    }, async calls => {
      assert.equal((await request('/v1/account', 'DELETE')).status, 502);
      if (failing === 'list') assert.equal(calls.some(c => c.path.startsWith('/auth/')), false);
    });
  }
  await mock(() => undefined, async calls => {
    assert.equal((await request('/v1/account', 'DELETE', undefined, false)).status, 401);
    assert.equal(calls.some(c => c.path.startsWith('/storage/') || c.path.startsWith('/auth/')), false);
  });
});
