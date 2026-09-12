import assert from "node:assert/strict";
Deno.env.set("SUPABASE_URL", "https://travelers.test");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-only-secret");
const {
  travelerDetails,
  travelerResponse,
  saveTraveler,
  deleteTraveler,
  listTravelers,
} = await import("../functions/travel-api/travelers.ts");
const { sealCheckout, openCheckout } = await import(
  "../functions/travel-api/hotel-checkouts.ts"
);
const owner = "11111111-1111-4111-8111-111111111111",
  id = "22222222-2222-4222-8222-222222222222",
  other = "33333333-3333-4333-8333-333333333333";
const details = {
  firstName: "Test",
  lastName: "Traveler",
  email: "test@example.test",
  phone: "+12125550123",
  nationality: "US",
};
Deno.test("traveler validation accepts only contact and valid nationality fields", () => {
  assert.deepEqual(
    travelerDetails({
      ...details,
      firstName: " Test ",
      passport: "discard",
      owner: other,
    }),
    details,
  );
  for (
    const change of [
      { nationality: "XX" },
      { nationality: "us" },
      { email: "bad" },
      { phone: "2125550123" },
      { firstName: "<script>" },
    ]
  ) assert.throws(() => travelerDetails({ ...details, ...change }));
});
Deno.test("traveler ciphertext is random, authenticated and bound to both account and profile", async () => {
  const private_payload = await sealCheckout(
    details,
    "traveler-v1:" + owner + ":" + id,
  );
  assert.notEqual(
    private_payload,
    await sealCheckout(details, "traveler-v1:" + owner + ":" + id),
  );
  assert(!private_payload.includes(details.email));
  const row = { owner, id, private_payload, version: 1, is_default: true };
  assert.deepEqual((await travelerResponse(owner, [row])).profiles, [{
    id,
    version: 1,
    isDefault: true,
    ...details,
  }]);
  await assert.rejects(() => travelerResponse(other, [row]));
  await assert.rejects(() =>
    travelerResponse(other, [{ ...row, owner: other }])
  );
  await assert.rejects(() => travelerResponse(owner, [{ ...row, id: other }]));
  await assert.rejects(() =>
    travelerResponse(owner, [{ ...row, private_payload: "bad" }])
  );
  await assert.rejects(() => travelerResponse(owner, Array(21).fill(row)));
});
Deno.test("traveler writes encrypt an allowlist and pass actor plus optimistic version to RPC", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async (input, init) => {
    assert.equal(
      String(input),
      "https://travelers.test/rest/v1/rpc/travel_traveler_save",
    );
    const body = JSON.parse(String(init?.body));
    assert.equal(body.actor, owner);
    assert.equal(body.target, id);
    assert.equal(body.expected_version, 3);
    assert.equal(body.make_default, true);
    assert.deepEqual(
      await openCheckout(body.payload, "traveler-v1:" + owner + ":" + id),
      details,
    );
    return Response.json([{
      owner,
      id,
      private_payload: body.payload,
      version: 4,
      is_default: true,
    }]);
  };
  try {
    const result = await saveTraveler(owner, id, {
      ...details,
      expectedVersion: 3,
      isDefault: true,
      passport: "discard",
      owner: other,
    });
    assert.equal(result.profiles[0].version, 4);
  } finally {
    globalThis.fetch = original;
  }
});
Deno.test("traveler collection and deletion are scoped to authenticated owner", async () => {
  const original = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async (input, init) => {
    calls++;
    if (init?.method === "POST") {
      assert(String(input).endsWith("/rpc/travel_traveler_delete"));
      assert.deepEqual(JSON.parse(String(init.body)), {
        actor: owner,
        target: id,
        expected_version: 2,
      });
    } else {
      assert(String(input).includes("owner=eq." + owner));
      assert(String(input).endsWith("&limit=21"));
    }
    return Response.json([]);
  };
  try {
    assert.deepEqual(await listTravelers(owner), { profiles: [] });
    assert.deepEqual(await deleteTraveler(owner, id, { expectedVersion: 2 }), {
      profiles: [],
    });
    assert.equal(calls, 2);
    for (const version of [-1, 0, 1.5, "1"]) {
      await assert.rejects(() =>
        deleteTraveler(owner, id, { expectedVersion: version })
      );
    }
    await assert.rejects(() =>
      saveTraveler(owner, id, {
        ...details,
        expectedVersion: -1,
        isDefault: true,
      })
    );
    assert.equal(calls, 2);
  } finally {
    globalThis.fetch = original;
  }
});
